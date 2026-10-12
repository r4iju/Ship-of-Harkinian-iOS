#import <AVFoundation/AVFoundation.h>
#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif

#include "DialogueVoices.h"
#include "soh/Enhancements/game-interactor/GameInteractor.h"
#include "soh/ShipInit.hpp"
#include <libultraship/bridge.h>
#include <nlohmann/json.hpp>
#include <spdlog/spdlog.h>
#include <algorithm>
#include <atomic>
#include <cctype>
#include <fstream>
#include <unordered_map>

extern "C" PlayState* gPlayState;
std::string Message_TTS_Decode(uint8_t* sourceBuf, uint16_t startOffset, uint16_t size);

@interface SOHDialogueVoiceDelegate : NSObject <AVAudioPlayerDelegate>
@end

@implementation SOHDialogueVoiceDelegate
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer*)audioPlayer successfully:(BOOL)success {
    if (CVarGetInteger(CVAR_SETTING("DialogueVoiceDebug"), 0)) {
        SPDLOG_INFO("Dialogue voice completed: {}, success={}", audioPlayer.url.lastPathComponent.UTF8String,
                    static_cast<bool>(success));
    }
}
- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer*)audioPlayer error:(NSError*)error {
    SPDLOG_WARN("Dialogue voice decoding failed: {}", error.localizedDescription.UTF8String);
}
@end

namespace {
struct Clip {
    std::string file;
    std::string voice;
};
std::unordered_map<std::string, Clip> clips;
std::string packDirectory;
AVAudioPlayer* player;
SOHDialogueVoiceDelegate* playerDelegate;
NSMutableArray* observers;
std::atomic<bool> background{ false };
bool awaitingPage = false;
bool suspended = false;
bool reportedProgress = false;

std::string PageKey(uint16_t textId, const std::string& text) {
    std::string key = std::to_string(textId) + ":";
    // Wrapping and presentation punctuation can differ after the game's decoder runs.
    for (unsigned char c : text) {
        if (std::isalnum(c) || c >= 0x80) {
            key += static_cast<char>(std::tolower(c));
        }
    }
    return key;
}

bool Enabled() {
    return CVarGetInteger(CVAR_SETTING("DialogueVoices"), 1) &&
           CVarGetInteger(CVAR_SETTING("Languages"), LANGUAGE_ENG) == LANGUAGE_ENG;
}

auto FindCurrentPage() {
    if (!gPlayState) {
        return clips.end();
    }
    auto& msg = gPlayState->msgCtx;
    auto text = Message_TTS_Decode(msg.msgBufDecoded, 0,
                                  std::min<size_t>(msg.decodedTextLen, sizeof(msg.msgBufDecoded)));
    return clips.find(PageKey(msg.textId, text));
}

void Stop() {
    if (player && CVarGetInteger(CVAR_SETTING("DialogueVoiceDebug"), 0)) {
        SPDLOG_INFO("Dialogue voice stopped at {:.2f}/{:.2f}s", player.currentTime, player.duration);
    }
    [player stop];
    player = nil;
    suspended = false;
    reportedProgress = false;
}

float Volume() {
    return std::clamp(CVarGetInteger(CVAR_SETTING("Volume.Master"), 40) / 100.0f, 0.0f, 1.0f) *
           std::clamp(CVarGetInteger(CVAR_SETTING("Volume.Dialogue"), 100) / 100.0f, 0.0f, 1.0f);
}

void UpdatePlayback() {
    if (!gPlayState || !Enabled()) {
        Stop();
        if (!gPlayState) {
            awaitingPage = false;
        }
        return;
    }
    if (!player) {
        return;
    }
    player.volume = Volume();
    bool shouldSuspend = background || (gPlayState && gPlayState->pauseCtx.state != 0);
    if (shouldSuspend && !suspended && player.isPlaying) {
        [player pause];
        suspended = true;
        if (CVarGetInteger(CVAR_SETTING("DialogueVoiceDebug"), 0)) {
            SPDLOG_INFO("Dialogue voice suspended at {:.2f}s", player.currentTime);
        }
    } else if (!shouldSuspend && suspended) {
        [player play];
        suspended = false;
        if (CVarGetInteger(CVAR_SETTING("DialogueVoiceDebug"), 0)) {
            SPDLOG_INFO("Dialogue voice resumed at {:.2f}s", player.currentTime);
        }
    }
    if (!reportedProgress && player.isPlaying && player.currentTime >= 0.25) {
        reportedProgress = true;
        if (CVarGetInteger(CVAR_SETTING("DialogueVoiceDebug"), 0)) {
            SPDLOG_INFO("Dialogue voice playback progressing: {:.2f}s, volume {:.2f}", player.currentTime,
                        player.volume);
        }
    }
}

void OnDialog() {
    if (!gPlayState) {
        return;
    }
    auto& msg = gPlayState->msgCtx;
    if (msg.msgMode == MSGMODE_TEXT_NEXT_MSG ||
        (msg.msgMode == MSGMODE_TEXT_CONTINUING && msg.stateTimer == 1)) {
        Stop();
        awaitingPage = true;
    } else if (msg.msgMode == MSGMODE_TEXT_DISPLAYING || msg.msgMode == MSGMODE_TEXT_AWAIT_NEXT ||
               msg.msgMode == MSGMODE_TEXT_DONE || msg.msgMode == MSGMODE_TEXT_DELAYED_BREAK) {
        if (!awaitingPage) {
            return;
        }
        awaitingPage = false;
        if (!Enabled()) {
            return;
        }
        auto found = FindCurrentPage();
        if (found == clips.end()) {
            if (CVarGetInteger(CVAR_SETTING("DialogueVoiceDebug"), 0)) {
                SPDLOG_INFO("Dialogue voice missing: {:04x}: {}", msg.textId,
                            Message_TTS_Decode(msg.msgBufDecoded, 0,
                                              std::min<size_t>(msg.decodedTextLen, sizeof(msg.msgBufDecoded))));
            }
            return;
        }
        NSError* error = nil;
        auto path = packDirectory + "/" + found->second.file;
        player = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@(path.c_str())] error:&error];
        player.delegate = playerDelegate;
        player.volume = Volume();
        if (!player || ![player prepareToPlay] || ![player play]) {
            SPDLOG_WARN("Could not play dialogue voice {}: {}", found->second.file,
                        error ? error.localizedDescription.UTF8String : "audio playback unavailable");
            Stop();
            return;
        }
        if (CVarGetInteger(CVAR_SETTING("DialogueVoiceDebug"), 0)) {
            SPDLOG_INFO("Dialogue voice started: {:04x}, {}, {}, {:.2f}s", msg.textId, found->second.voice,
                        found->second.file, player.duration);
        }
        UpdatePlayback();
    } else if (msg.msgMode == MSGMODE_NONE || msg.msgMode == MSGMODE_TEXT_CLOSING ||
               msg.msgMode == MSGMODE_TEXT_CONTINUING) {
        Stop();
        awaitingPage = false;
    }
}

void RegisterDialogueVoices() {
    NSString* directory = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"dialogue-voices"];
    if (!directory) {
        return;
    }
    packDirectory = directory.UTF8String;
    std::ifstream stream(packDirectory + "/manifest.json");
    if (!stream) {
        return;
    }
    try {
        auto manifest = nlohmann::json::parse(stream);
        if (manifest.at("version") != 1 || manifest.at("language") != "eng") {
            SPDLOG_WARN("Unsupported dialogue voice pack version or language");
            return;
        }
        for (const auto& entry : manifest.at("clips")) {
            auto file = entry.at("file").get<std::string>();
            if (file.empty() || file.find('/') != std::string::npos || file.find('\\') != std::string::npos ||
                file.find("..") != std::string::npos) {
                continue;
            }
            if (![[NSFileManager defaultManager] fileExistsAtPath:@((packDirectory + "/" + file).c_str())]) {
                continue;
            }
            auto key = PageKey(entry.at("text_id").get<uint16_t>(), entry.at("text").get<std::string>());
            clips.emplace(key, Clip{ file, entry.at("voice").get<std::string>() });
        }
    } catch (const std::exception& error) {
        clips.clear();
        SPDLOG_WARN("Could not load dialogue voice pack: {}", error.what());
        return;
    }
    SPDLOG_INFO("Loaded {} bundled dialogue voice pages", clips.size());
    playerDelegate = [SOHDialogueVoiceDelegate new];
    observers = [NSMutableArray new];
#if TARGET_OS_OSX
    NSString* resign = NSApplicationWillResignActiveNotification;
    NSString* active = NSApplicationDidBecomeActiveNotification;
#else
    NSString* resign = UIApplicationWillResignActiveNotification;
    NSString* active = UIApplicationDidBecomeActiveNotification;
#endif
    [observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:resign object:nil queue:nil
        usingBlock:^(NSNotification*) {
            background = true;
            UpdatePlayback();
        }]];
    [observers addObject:[NSNotificationCenter.defaultCenter addObserverForName:active object:nil queue:nil
        usingBlock:^(NSNotification*) {
            background = false;
            UpdatePlayback();
        }]];
    GameInteractor::Instance->RegisterGameHook<GameInteractor::OnDialogMessage>(OnDialog);
    GameInteractor::Instance->RegisterGameHook<GameInteractor::OnGameFrameUpdate>(UpdatePlayback);
    GameInteractor::Instance->RegisterGameHook<GameInteractor::OnSceneInit>([](int16_t) {
        Stop();
        awaitingPage = false;
    });
    GameInteractor::Instance->RegisterGameHook<GameInteractor::OnExitGame>([](int32_t) {
        Stop();
        awaitingPage = false;
    });
}
static RegisterShipInitFunc initFunc(RegisterDialogueVoices);
} // namespace

bool DialogueVoices_HasCurrentPage() {
    return Enabled() && FindCurrentPage() != clips.end();
}
