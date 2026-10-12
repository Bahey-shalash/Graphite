# Graphite's copy of mlx-audio-swift

Upstream: https://github.com/Blaizzy/mlx-audio-swift at commit 244458d7b61e54ff135073ddc9ed76782bb20758 (2026-10-10), MIT License (see `LICENSE`).

Graphite uses it to run Read Aloud's downloadable voices on the device with MLX. Only what those voices need is kept:

- Targets: `MLXAudioCore`, `MLXAudioCodecs`, `MLXAudioG2P`, `MLXAudioTTS`. The speech-to-text, voice activity, language identification, speech-to-speech and UI targets, the command-line tools, the tests and every README were removed.
- Models: `PocketTTS`, `Qwen3TTS`, `Chatterbox`, `Dia`. All other models were removed.
- Codecs: `Mimi`, `Descript`, `BigVGAN` (used by Descript), `S3`, `S3Gen`. All other codecs were removed.
- `TTSModel.swift` (the loader that picks a model by repository name and downloads from Hugging Face) was removed: Graphite loads each model from a folder it downloaded and verified itself (`NeuralSpeechEngine`).
- Dependencies are pinned to exact versions: mlx-swift 0.32.3, mlx-swift-lm 3.32.3, swift-transformers 1.3.4, swift-huggingface 0.12.0 (the versions upstream resolved at that commit).

## Changes to the kept code

Each is marked `GRAPHITE PATCH` in the source.

1. `Models/Chatterbox/ChatterboxModel.swift`: `fromModelDirectory` no longer downloads the 944 MB `mlx-community/S3TokenizerV2` from Hugging Face. It is needed only for voice cloning, which Graphite does not use, and nothing may be downloaded that the person did not ask for. An optional `s3TokenizerDirectory` loads it from disk instead.
2. `Models/Dia/DiaTTSModel.swift`:
   - `fromModelDirectory(_:codecDirectory:)` loads Dia and its Descript codec from folders on disk without network access.
   - `DiaVoicePrompt`, `voicePrompt` and `encodeVoicePrompt(samples:transcript:)` add Dia's audio-prompt mechanism (as in the Python mlx-audio implementation): the prompt's transcript is put before the text, its codec frames, delayed per channel, are run through the decoder in one prefill pass, generation continues after them, and the prompt's frames are cut from the result. Upstream ignored `refAudio`, so every request had a new random voice.
3. `Models/Qwen3TTS/Qwen3TTSSpeechTokenizer.swift`: `streamingStep` evaluates the decoder block by block. Left lazy, a two-second chunk's graph held about 2 GB of intermediates (MLX peak 4.4 GB instead of 3.1 GB on a Mac), and on an 8 GB iPad Pro M1 iOS ended the app at its 5.4 GB limit.
4. `Models/PocketTTS/PocketTTSModel.swift`: each frame's decoded audio is evaluated as it is made. Left lazy, the codec decoding of a whole passage ran as one graph at the end; on the iPad its footprint reached 4.8 GB for a 28-second passage.

## Updating

Copy the kept directories from a newer upstream commit, reapply the changes above (search for `GRAPHITE PATCH` in this copy), update the commit and versions here and in `Package.swift`, and run the voice benchmark on a device again (`Docs/Architecture.md`, Read Aloud voices).
