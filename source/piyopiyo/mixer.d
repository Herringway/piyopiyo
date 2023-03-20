module piyopiyo.mixer;

import piyopiyo.interpolation;
import std.algorithm.comparison : clamp, max, min;
import std.math : pow;

struct Mixer {
	private static struct Sound {
		private const(byte)[] samples;
		private size_t position;
		private ushort positionSubsample;
		private uint advanceDelta;
		private bool playing;
		private bool looping;
		private short volumeShared;
		private short panL;
		private short panR;
		private short volumeL;
		private short volumeR;

		void pan(int val) @safe pure nothrow {
			panL = millibelToScale(-val);
			panR = millibelToScale(val);

			volumeL = cast(short)((panL * volumeShared) >> 8);
			volumeR = cast(short)((panR * volumeShared) >> 8);
		}
		void volume(short val) @safe pure nothrow {
			volumeShared = millibelToScale(val);

			volumeL = cast(short)((panL * volumeShared) >> 8);
			volumeR = cast(short)((panR * volumeShared) >> 8);
		}
		void frequency(uint val) @safe pure nothrow {
			advanceDelta = val << 16;
		}
		void play(bool loop) @safe pure nothrow {
			playing = true;
			looping = loop;

		}
		void stop() @safe pure nothrow {
			playing = false;
		}
		void seek(size_t position) @safe pure nothrow {
			this.position = position;
			positionSubsample = 0;
		}
	}
	private InterpolationMethod interpolationMethod;
	private uint outputFrequency = 48000;
	private Sound[] activeSoundList;
	ref Sound getSound(size_t id) @safe pure nothrow {
		return activeSoundList[id];
	}
	size_t createSound(uint inFrequency, const(ubyte)[] inSamples) @safe pure {
		activeSoundList.length++;

		auto newSamples = new byte[](inSamples.length);

		with (activeSoundList[$ - 1]) {
			foreach (idx, ref sample; newSamples) {
				sample = inSamples[idx] - 0x80;
			}
			samples = newSamples;

			playing = false;
			position = 0;
			positionSubsample = 0;

			frequency = inFrequency;
			volume = 0;
			pan = 0;
		}
		//sound.next = activeSoundList;
		//activeSoundList = sound;

		return activeSoundList.length - 1;
	}
	void mixSounds(scope short[2][] stream) @safe pure nothrow {
		foreach (ref sound; activeSoundList) {
			if (!sound.playing) {
				continue;
			}
			short[2][] streamPointer = stream;

			for (size_t framesDone = 0; framesDone < stream.length; ++framesDone) {
				// Interpolate the samples
				byte[8] interpolationBuffer;
				const remaining = max(cast(ptrdiff_t)0, cast(ptrdiff_t)(interpolationBuffer.length - (sound.samples.length - sound.position)));
				interpolationBuffer[0 .. $ - remaining] = sound.samples[sound.position .. min($, sound.position + 8)];
				if (sound.looping && (remaining > 0)) {
					interpolationBuffer[$ - remaining .. $] = sound.samples[0 .. remaining];
				}
				const outputSample = interpolate(interpolationMethod, interpolationBuffer[], sound.positionSubsample);

				// Mix, and apply volume

				streamPointer[0][0] = cast(short)clamp(streamPointer[0][0] + outputSample * sound.volumeL, short.min, short.max);
				streamPointer[0][1] = cast(short)clamp(streamPointer[0][1] + outputSample * sound.volumeR, short.min, short.max);
				streamPointer = streamPointer[1 .. $];

				// Increment sample
				const uint nextPositionSubsample = sound.positionSubsample + sound.advanceDelta / outputFrequency;
				sound.position += nextPositionSubsample >> 16;
				sound.positionSubsample = nextPositionSubsample & 0xFFFF;

				// Stop or loop sample once it's reached its end
				if (sound.position >= (sound.samples.length)) {
					if (sound.looping) {
						sound.position %= sound.samples.length;
					} else {
						sound.playing = false;
						sound.position = 0;
						sound.positionSubsample = 0;
						break;
					}
				}
			}
		}
	}
}

private ushort millibelToScale(int volume) @safe pure @nogc nothrow {
	// Volume is in hundredths of a decibel, from 0 to -10000
	volume = clamp(volume, -10000, 0);
	return cast(ushort)(pow(10.0, volume / 2000.0) * 256.0);
}
