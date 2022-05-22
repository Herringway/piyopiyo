module smixer;

import std.algorithm.comparison;
import std.experimental.logger;
import std.math;

enum SoundPlayFlags {
	normal,
	looping
}


struct Mixer_Sound {
	byte[] samples;
	size_t position;
	ushort position_subsample;
	uint advance_delta;
	bool playing;
	bool looping;
	short _volume;
	short pan_l;
	short pan_r;
	short volume_l;
	short volume_r;

	Mixer_Sound* next;
	void pan(int val) @safe nothrow {
		pan_l = MillibelToScale(-val);
		pan_r = MillibelToScale(val);

		volume_l = cast(short)((pan_l * _volume) >> 8);
		volume_r = cast(short)((pan_r * _volume) >> 8);
	}
	void volume(short val) @safe nothrow {
		_volume = MillibelToScale(val);

		volume_l = cast(short)((pan_l * _volume) >> 8);
		volume_r = cast(short)((pan_r * _volume) >> 8);
	}
	void frequency(uint val) @safe {
		assert(output_frequency != 0, "Output frequency cannot be zero");
		advance_delta = (val << 16) / output_frequency;
	}
	void play(bool loop) @safe nothrow {
		playing = true;
		looping = loop;

		samples[$ - 1] = loop ? samples[0] : 0;

	}
	void stop() @safe nothrow {
		playing = false;
	}
}

private enum output_frequency = 48000;
struct SoftwareMixer {
	Mixer mixer;
	private void delegate() @safe nothrow callback;
	private uint callback_timer_master;
	alias Sound = Mixer_Sound;

	void mixSoundsAndUpdateMusic(scope int[] stream) @safe nothrow {
		if (callback_timer_master == 0) {
			mixer.mixSounds(stream);
		} else {
			uint frames_done = 0;

			while (frames_done != stream.length / 2) {
				static ulong callback_timer;

				if (callback_timer == 0) {
					callback_timer = callback_timer_master;
					callback();
				}

				const ulong frames_to_do = min(callback_timer, stream.length / 2 - frames_done);

				mixer.mixSounds(stream[frames_done * 2 .. frames_done * 2 + frames_to_do * 2]);

				frames_done += frames_to_do;
				callback_timer -= frames_to_do;
			}
		}
	}

	Sound* createSound(uint frequency, const(ubyte)[] samples) @safe {
		return mixer.createSound(frequency, samples);
	}

	void destroySound(ref Sound sound) @safe {
		mixer.destroySound(sound);
	}

	void play(ref Sound sound, SoundPlayFlags flags) @safe nothrow {
		sound.play(flags == SoundPlayFlags.looping);
	}

	void stop(ref Sound sound) @safe nothrow {
		sound.stop();
	}

	void seek(ref Sound sound, uint position) @safe nothrow {
		sound.position = position;
		sound.position_subsample = 0;
	}

	void setFrequency(ref Sound sound, uint frequency) {
		sound.frequency = frequency;
	}

	void setVolume(ref Sound sound, int volume) {
		sound.volume = cast(short)volume;
	}

	void setPan(ref Sound sound, int pan) {
		sound.pan = pan;
	}

	void setMusicCallback(void delegate() @safe nothrow callback) @safe {
		this.callback = callback;
	}

	void setMusicTimer(uint milliseconds) @safe {
		callback_timer_master = (milliseconds * output_frequency) / 1000;
	}
}


private ushort MillibelToScale(int volume) @safe pure @nogc nothrow {
	// Volume is in hundredths of a decibel, from 0 to -10000
	volume = clamp(volume, -10000, 0);
	return cast(ushort)(pow(10.0, volume / 2000.0) * 256.0);
}

struct Mixer {
	private Mixer_Sound *sound_list_head;
	Mixer_Sound* createSound(uint frequency, const(ubyte)[] samples) @safe {
		Mixer_Sound* sound = new Mixer_Sound();

		if (sound == null)
			return null;

		sound.samples = new byte[](samples.length + 1);

		if (sound.samples == null) {
			return null;
		}

		foreach (idx, ref sample; sound.samples[0 .. $ - 1]) {
			sample = samples[idx] - 0x80;
		}

		sound.playing = false;
		sound.position = 0;
		sound.position_subsample = 0;

		sound.frequency = frequency;
		sound.volume = 0;
		sound.pan = 0;

		sound.next = sound_list_head;
		sound_list_head = sound;

		return sound;
	}

	void destroySound(ref Mixer_Sound sound) @safe {
		for (Mixer_Sound** sound_pointer = &sound_list_head; *sound_pointer != null; sound_pointer = &(*sound_pointer).next) {
			if (**sound_pointer == sound) {
				*sound_pointer = sound.next;
				break;
			}
		}
	}

	void mixSounds(scope int[] stream) @safe nothrow {
		for (Mixer_Sound* sound = sound_list_head; sound != null; sound = sound.next) {
			if (sound.playing) {
				int[] stream_pointer = stream;

				for (size_t frames_done = 0; frames_done < stream.length / 2; ++frames_done) {
					// Perform linear interpolation
					const ubyte interpolation_scale = sound.position_subsample >> 8;

					const byte output_sample = cast(byte)((sound.samples[sound.position] * (0x100 - interpolation_scale)
									                                 + sound.samples[sound.position + 1] * interpolation_scale) >> 8);

					// Mix, and apply volume

					stream_pointer[0] += output_sample * sound.volume_l;
					stream_pointer[1] += output_sample * sound.volume_r;
					stream_pointer = stream_pointer[2 .. $];

					// Increment sample
					const uint next_position_subsample = sound.position_subsample + sound.advance_delta;
					sound.position += next_position_subsample >> 16;
					sound.position_subsample = next_position_subsample & 0xFFFF;

					// Stop or loop sample once it's reached its end
					if (sound.position >= (sound.samples.length - 1)) {
						if (sound.looping) {
							sound.position %= sound.samples.length - 1;
						} else {
							sound.playing = false;
							sound.position = 0;
							sound.position_subsample = 0;
							break;
						}
					}
				}
			}
		}
	}
}
