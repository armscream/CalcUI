//* The sound of SDL3: a WAV file of 16 bit PCM is read, and its frames
//* are put into the stream of the audio device. The GUI knows nothing
//* of SDL: it only has the binding of the sound.
package Backend

import GUI "../GUI"
import sdl "vendor:sdl3"
import "core:log"
import "core:math"
import "core:os"

//* == The WAV file ==

//* A WAV file of 16 bit PCM: the rate, the channels and the frames.
WAV_Sound :: struct {
  channels: int,
  rate:     int,
  frames:   []u8,
}

//* Reads a WAV file of 16 bit PCM. The frames are in the memory of the
//* caller, who has to give them back with `delete`.
wav_read :: proc(path: string) -> (sound: WAV_Sound, ok: bool) {
  file, err := os.read_entire_file_from_path(path, context.allocator)
  if err != nil {return WAV_Sound{}, false}
  defer delete(file)
  return wav_parse(file)
}

//* Looks through the chunks of a RIFF file for the format of the sound
//* and for its frames.
wav_parse :: proc(file: []u8) -> (sound: WAV_Sound, ok: bool) {
  if len(file) < 44 {return WAV_Sound{}, false}
  if !wav_tag(file[0:4], "RIFF") {return WAV_Sound{}, false}
  if !wav_tag(file[8:12], "WAVE") {return WAV_Sound{}, false}

  format := u16(0)
  channels := 0
  rate := 0
  bits := 0
  start := 0
  size := 0
  have_format := false
  have_data := false

  at := 12
  for at + 8 <= len(file) {
    tag := file[at:at+4]
    chunk := int(wav_u32(file, at+4))
    body := at + 8
    if chunk > len(file) - body {break}
    if wav_tag(tag, "fmt ") {
      if chunk < 16 {return WAV_Sound{}, false}
      format = wav_u16(file, body)
      channels = int(wav_u16(file, body+2))
      rate = int(wav_u32(file, body+4))
      bits = int(wav_u16(file, body+14))
      have_format = true
      //* The sound that says that it is extensible keeps the real
      //* format in the first two bytes of its tail.
      if format == 0xFFFE {
        if chunk < 40 {return WAV_Sound{}, false}
        if wav_u16(file, body+24) != 1 {return WAV_Sound{}, false}
      }
    } else if wav_tag(tag, "data") {
      start = body
      size = chunk
      have_data = true
    }
    //* The chunks are padded to an even size.
    at = body + chunk + chunk % 2
  }

  if !have_format || !have_data {return WAV_Sound{}, false}
  //* Only the plain PCM of 16 bits is read.
  if format != 1 && format != 0xFFFE {return WAV_Sound{}, false}
  if bits != 16 {return WAV_Sound{}, false}
  if channels < 1 || rate < 1 {return WAV_Sound{}, false}
  if size < 1 {return WAV_Sound{}, false}

  //* The frames that are left over are thrown away: the device cannot
  //* play half a frame.
  frame := channels * 2
  size -= size % frame
  if size < 1 {return WAV_Sound{}, false}

  frames := make([]u8, size)
  copy(frames, file[start:start+size])
  return WAV_Sound{channels = channels, rate = rate, frames = frames}, true
}

//* Says whether four bytes are the tag of a chunk.
wav_tag :: proc(bytes: []u8, tag: string) -> bool {
  if len(bytes) < 4 || len(tag) < 4 {return false}
  return bytes[0] == tag[0] && bytes[1] == tag[1] && bytes[2] == tag[2] && bytes[3] == tag[3]
}

//* The small numbers of a RIFF file are little endian.
wav_u16 :: proc(bytes: []u8, at: int) -> u16 {
  return u16(bytes[at]) | (u16(bytes[at+1]) << 8)
}

wav_u32 :: proc(bytes: []u8, at: int) -> u32 {
  return u32(bytes[at]) | (u32(bytes[at+1]) << 8) | (u32(bytes[at+2]) << 16) | (u32(bytes[at+3]) << 24)
}

//* == The device ==

//* The sound of one GUI: the device of SDL, the stream that is bound to
//* it, and what is in the stream.
SDL3_Audio :: struct {
  device: sdl.AudioDeviceID,
  open:   bool,
  stream: ^sdl.AudioStream,
  //* The format of the device, as SDL made it.
  spec:   sdl.AudioSpec,
  //* How many bytes were put into the stream for the sound that plays.
  put:    int,
  //* The rate and the channels of the sound that plays, so that the
  //* position can be told in seconds.
  rate:     int,
  channels: int,
  //* How loud the sound is, from 0 to 1.
  gain:   f32,
}

//* The sounds of the GUIs that have one. The key is the GUI itself.
sdl3_audios: map[rawptr]^SDL3_Audio

//* The sound of a GUI, when it has one.
sdl3_audio_of :: proc(g: ^GUI.GUI) -> ^SDL3_Audio {
  if g == nil {return nil}
  return sdl3_audios[cast(rawptr)g]
}

//* Opens the audio device of SDL and gives the GUI its sound. Gives
//* false back when there is no device: the GUI stays usable without
//* sound.
sdl3_audio_install :: proc(g: ^GUI.GUI) -> bool {
  if g == nil {return false}
  if sdl3_audio_of(g) != nil {return true}

  if !sdl.InitSubSystem(sdl.INIT_AUDIO) {
    log.warnf("the sound of SDL did not start: %s", sdl.GetError())
    return false
  }

  spec := sdl.AudioSpec {
    format   = sdl.AudioFormat.S16LE,
    channels = 2,
    freq     = 44100,
  }
  device := sdl.OpenAudioDevice(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec)
  if device == 0 {
    log.warnf("there is no sound device: %s", sdl.GetError())
    return false
  }

  audio := new(SDL3_Audio)
  audio.device = device
  audio.open = true
  audio.gain = 1
  //* The device may have taken another format than the one that was
  //* asked for.
  sdl.GetAudioDeviceFormat(device, &audio.spec, nil)

  if sdl3_audios == nil {
    sdl3_audios = make(map[rawptr]^SDL3_Audio)
  }
  sdl3_audios[cast(rawptr)g] = audio

  GUI.audio_set_binding(g, GUI.Audio_Binding {
    play     = sdl3_audio_play,
    stop     = sdl3_audio_stop,
    position = sdl3_audio_position,
    volume   = sdl3_audio_volume,
  })

  //* The loudness the GUI has is the loudness of the device.
  sdl3_audio_volume(g, GUI.audio_volume(g))
  return true
}

//* Closes the sound of a GUI and throws it away.
sdl3_audio_shutdown :: proc(g: ^GUI.GUI) {
  if g == nil {return}
  audio := sdl3_audio_of(g)
  if audio == nil {return}
  sdl3_audio_clear(audio)
  if audio.open {
    sdl.CloseAudioDevice(audio.device)
    audio.open = false
  }
  delete_key(&sdl3_audios, cast(rawptr)g)
  if len(sdl3_audios) == 0 {
    delete(sdl3_audios)
    sdl3_audios = nil
  }
  free(audio)
}

//* Throws the sound that plays away: the stream is unbound and
//* destroyed, so the device has nothing left to play.
sdl3_audio_clear :: proc(audio: ^SDL3_Audio) {
  if audio == nil {return}
  if audio.stream != nil {
    sdl.UnbindAudioStream(audio.stream)
    sdl.DestroyAudioStream(audio.stream)
    audio.stream = nil
  }
  audio.put = 0
  audio.rate = 0
  audio.channels = 0
}

//* Starts a sound and says how long it is, in seconds.
sdl3_audio_play :: proc(g: ^GUI.GUI, path: string) -> f32 {
  audio := sdl3_audio_of(g)
  if audio == nil {return 0}
  sound, ok := wav_read(path)
  if !ok {
    log.warnf("the sound %q could not be read", path)
    return 0
  }
  defer delete(sound.frames)

  //* The sound that was playing is thrown away.
  sdl3_audio_clear(audio)

  src := sdl.AudioSpec {
    format   = sdl.AudioFormat.S16LE,
    channels = i32(sound.channels),
    freq     = i32(sound.rate),
  }
  stream := sdl.CreateAudioStream(&src, &audio.spec)
  if stream == nil {return 0}
  audio.stream = stream
  if !sdl.BindAudioStream(audio.device, stream) {
    sdl3_audio_clear(audio)
    return 0
  }
  if !sdl.PutAudioStreamData(stream, raw_data(sound.frames), i32(len(sound.frames))) {
    sdl3_audio_clear(audio)
    return 0
  }

  audio.put = len(sound.frames)
  audio.rate = sound.rate
  audio.channels = sound.channels
  //* The device waits when the sound is stopped.
  sdl.ResumeAudioDevice(audio.device)
  return sdl3_audio_length(audio)
}

//* Stops the sound.
sdl3_audio_stop :: proc(g: ^GUI.GUI) {
  audio := sdl3_audio_of(g)
  if audio == nil {return}
  //* The device is held still, so that the sound stops at once.
  sdl.PauseAudioDevice(audio.device)
  sdl3_audio_clear(audio)
}

//* How far the sound has come, in seconds.
sdl3_audio_position :: proc(g: ^GUI.GUI) -> f32 {
  audio := sdl3_audio_of(g)
  if audio == nil {return 0}
  if audio.stream == nil {return 0}
  queued := sdl.GetAudioStreamQueued(audio.stream)
  if queued < 0 {return 0}
  //* The bytes that are still in the stream are the ones the device
  //* has not taken yet.
  consumed := audio.put - int(queued)
  if consumed <= 0 {return 0}
  frame := sdl3_audio_frame(audio)
  if frame <= 0 {return 0}
  return f32(consumed) / f32(frame)
}

//* Sets how loud the sound is, from 0 to 1.
sdl3_audio_volume :: proc(g: ^GUI.GUI, volume: f32) {
  audio := sdl3_audio_of(g)
  if audio == nil {return}
  audio.gain = clamp(volume, 0, 1)
  sdl.SetAudioDeviceGain(audio.device, audio.gain)
}

//* How long the sound that plays is, in seconds.
sdl3_audio_length :: proc(audio: ^SDL3_Audio) -> f32 {
  frame := sdl3_audio_frame(audio)
  if frame <= 0 {return 0}
  return f32(audio.put) / f32(frame)
}

//* How many bytes one frame of the sound takes: the channels, each of
//* them 16 bits.
sdl3_audio_frame :: proc(audio: ^SDL3_Audio) -> int {
  if audio == nil {return 0}
  return audio.rate * audio.channels * 2
}
