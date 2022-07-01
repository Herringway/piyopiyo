module pixel.piyopiyo;

import std.algorithm.comparison;
import std.experimental.logger;
import std.math;

import core.time;

private immutable int[12] freqTable = [ 1551, 1652, 1747, 1848, 1955, 2074, 2205, 2324, 2461, 2616, 2770, 2938 ];

private enum SoundMode {
	playLoop,
	stop,
	play
}

private enum maxRecord = 1000;

private struct TrackHeader {
	//Track information
	ubyte octave;
	ubyte icon;
	uint length;
	uint volume;
	uint unused1;
	uint unused2;
	byte[0x100] wave;
	ubyte[0x40] envelope;
}
static assert(TrackHeader.sizeof == 0x154);

private struct Header {
	char[3] magic;
	bool writable;
	uint pTrack1;
	uint wait;
	int repeatX;
	int endX;
	int records;

	//Track headers
	TrackHeader[3] track;
	uint percussionVolume;
}
static assert(Header.sizeof == 0x418);

struct PiyoPiyo {
	//Loaded header
	private Header header;

	//Playback state
	private bool playing;
	private int position;
	private MonoTime tick;
	private uint[maxRecord][4] record;
	private bool initialized;
	private int volume;
	private bool fading;
	private MixerSound*[int] loadedSamples;
	private uint sampleRate;
	private uint masterTimer;
	private MixerSound *activeSoundList;
	public void initialize(uint sampleRate) @safe {
		loadedSamples[472] = loadWav(wavBASS1);
		loadedSamples[473] = loadWav(wavBASS1);
		loadedSamples[474] = loadWav(wavBASS2);
		loadedSamples[475] = loadWav(wavBASS2);
		loadedSamples[476] = loadWav(wavSNARE1);
		loadedSamples[477] = loadWav(wavSNARE1);
		loadedSamples[478] = loadWav(wavSNARE1);
		loadedSamples[479] = loadWav(wavSNARE1);
		loadedSamples[480] = loadWav(wavHAT1);
		loadedSamples[481] = loadWav(wavHAT1);
		loadedSamples[482] = loadWav(wavHAT2);
		loadedSamples[483] = loadWav(wavHAT2);
		loadedSamples[484] = loadWav(wavSYMBAL1);
		loadedSamples[485] = loadWav(wavSYMBAL1);
		loadedSamples[486] = loadWav(wavSYMBAL1);
		loadedSamples[487] = loadWav(wavSYMBAL1);
		loadedSamples[488] = loadWav(wavSYMBAL1);
		loadedSamples[489] = loadWav(wavSYMBAL1);
		loadedSamples[490] = loadWav(wavSYMBAL1);
		loadedSamples[491] = loadWav(wavSYMBAL1);
		loadedSamples[492] = loadWav(wavSYMBAL1);
		loadedSamples[493] = loadWav(wavSYMBAL1);
		loadedSamples[494] = loadWav(wavSYMBAL1);
		loadedSamples[495] = loadWav(wavSYMBAL1);
		initialized = true;

		this.sampleRate = sampleRate;
	}
	private bool readData(const ubyte[] data) @safe {
		//Fail if PiyoPiyo hasn't been initialised
		if (initialized == false)
			return false;

		//Read data
		header = (cast(const(Header[]))(data[0 .. Header.sizeof]))[0];
		record[0][0 .. header.records] = cast(const(uint[]))(data[Header.sizeof + header.records * 0 * uint.sizeof .. Header.sizeof + header.records * 1 * uint.sizeof]);
		record[1][0 .. header.records] = cast(const(uint[]))(data[Header.sizeof + header.records * 1 * uint.sizeof .. Header.sizeof + header.records * 2 * uint.sizeof]);
		record[2][0 .. header.records] = cast(const(uint[]))(data[Header.sizeof + header.records * 2 * uint.sizeof .. Header.sizeof + header.records * 3 * uint.sizeof]);
		record[3][0 .. header.records] = cast(const(uint[]))(data[Header.sizeof + header.records * 3 * uint.sizeof .. Header.sizeof + header.records * 4 * uint.sizeof]);
		position = -1;
		fading = false;
		return true;
	}
	private void update() @safe nothrow {
		static immutable int[8] panTable = [
			0, 96, 180, 224, 256, 288, 332, 420
		];

		//Check if next step should be played
		if (initialized && playing && MonoTime.currTime() > (tick + header.wait.msecs)) {
			if (fading) {
				if (volume < 250) {
					changeVolume(volume + 1);
				} else {
					fading = false;
					playing = false;
				}
			}
			//Check if position passes loop point
			if (position++ > (header.endX - 1) || position > (header.records - 1)) {
				position = header.repeatX;
			}

			//Step channels
			for (int i = 0; i < 4; i++) {
				//Get this record
				uint record = record[i][position];

				//Change pan
				if (record & 0xFF000000) {
					int pan = record >> 24;
					for (int j = 0; j < 24; j++) {
						if (auto sample = (400 + (i * 24) + j) in loadedSamples) {
							(*sample).pan = (panTable[pan] - 256) * 10;
						}
					}
				}

				//Play notes
				for (int j = 0; j < 24; j++) {
					if (record & 1) {
						playSoundObject(400 + (i * 24) + j, SoundMode.play);
					}
					record >>= 1;
				}
			}

			//Remember previous tick
			tick = MonoTime.currTime();
		}
	}
	private void makeSoundObjects() @safe {
		//Make sure PiyoPiyo has been initialised
		if (initialized) {
			//Setup each melody track
			for (int i = 0; i < 3; i++) {
				//Get octave
				int octave = 1 << header.track[i].octave;

				//Release previous objects
				for (int j = 0; j < 24; j++) {
					releaseSoundObject(400 + (i * 24) + j);
				}

				//Make new objects
				makeSoundObject(
					header.track[i].wave[],
					header.track[i].envelope[],
					octave,
					header.track[i].length,
					400 + (24 * i));
			}
			changeVolume(0);
		}
	}

	public void changeVolume(int volume) @safe nothrow {
		volume = volume;
		//(volume - 300) * 8)
		if (initialized) {
			//Set melody volume
			for (int i = 0; i < 3; i++) {
				for (int j = 0; j < 24; j++) {
					loadedSamples[400 + (i * 24) + j].volume = cast(short)((header.track[i].volume - volume - 300) * 8);
				}
			}

			//Set drum volume
			for (int i = 0; i < 24; i += 2) {
				loadedSamples[472 + i].volume = cast(short)((header.percussionVolume - volume - 300) * 8);
				loadedSamples[473 + i].volume = cast(short)((70 * header.percussionVolume / 100 - volume - 300) * 8);
			}
		}
	}
	public void play() @safe {
		playing = true;
		setMusicTimer(20);
	}

	public void stop() @safe {
		playing = false;
		setMusicTimer(0);
	}

	public void loadMusic(const ubyte[] data) @safe {
		readData(data);
		makeSoundObjects();
	}

	public void setFadeout() @safe {
		fading = true;
	}

	public void setPosition(uint position) @safe {
		position = position;
	}
	public uint getPosition() @safe {
		return position;
	}

	private bool makeSoundObject(byte[] wave, ubyte[] envelope, int octave, int dataSize, int no) @safe {
		bool result;
		int i;

		//Write sound data
		ubyte[] wp = new ubyte[](dataSize);

		for (i = 0; i < 24; i++) {
			//Construct waveform
			int wpSub = 0;
			int envelopeI = 0;

			for (int j = 0; j < dataSize; j++) {
				//Get sample
				int sample = wave[cast(ubyte)(wpSub / 256)];
				envelopeI = (j << 6) / dataSize;
				sample = sample * envelope[envelopeI] / 128;

				//Set sample
				wp[j] = cast(ubyte)(sample + 0x80);

				//Increase sub-pos
				int freq;
				if (i < 12) {
					freq = octave * freqTable[i] / 16;
				} else {
					freq = octave * freqTable[i - 12] / 8;
				}
				wpSub += freq;
			}
			loadedSamples[no + i] = createSound(22050, wp);
		}

		//Check if there was an error and free wave buffer
		if (i == 24) {
			result = true;
		}
		return result;
	}
	private void playSoundObject(int no, int mode) @safe nothrow {
		if (auto sample = no in loadedSamples) {
			switch (mode) {
				case SoundMode.stop:
					(*sample).stop();
					break;

				case SoundMode.play:
					(*sample).stop();
					(*sample).seek(0);
					(*sample).play(false);
					break;

				case SoundMode.playLoop:
					(*sample).play(true);
					break;
				default: break;
			}
		}
	}
	private void releaseSoundObject(int no) @safe {
		if (auto sample = no in loadedSamples) {
			destroySound(**sample);
		}
	}
	private MixerSound* loadWav(const(ubyte)[] data) @safe {
		if (data == null) { //uh oh. no audio. use an empty sample
			return createSound(22050, []);
		}
		auto wav = (cast(const(WAVFile)[])(data)[0 .. WAVFile.sizeof])[0];
		return createSound(cast(ushort)wav.numSamplesPerSec, data[wav.data.offsetof .. wav.data.offsetof + wav.subchunk2Size]);
	}

	public void fillBuffer(scope short[] finalBuffer) @safe nothrow {
		int[0x800 * 2] buffer;
		auto stream = buffer[0 .. finalBuffer.length];
		if (masterTimer == 0) {
			mixSounds(stream);
		} else {
			uint framesDone = 0;

			while (framesDone != stream.length / 2) {
				static ulong updateTimer;

				if (updateTimer == 0) {
					updateTimer = masterTimer;
					update();
				}

				const ulong framesToDo = min(updateTimer, stream.length / 2 - framesDone);

				mixSounds(stream[framesDone * 2 .. framesDone * 2 + framesToDo * 2]);

				framesDone += framesToDo;
				updateTimer -= framesToDo;
			}
		}
		for (size_t i = 0; i < finalBuffer.length; ++i) {
			finalBuffer[i] = cast(short)clamp(buffer[i], short.min, short.max);
		}
	}

	private void setMusicTimer(uint milliseconds) @safe {
		masterTimer = (milliseconds * sampleRate) / 1000;
	}
	private MixerSound* createSound(uint frequency, const(ubyte)[] samples) @safe {
		MixerSound* sound = new MixerSound();

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
		sound.positionSubsample = 0;

		sound.frequency = frequency;
		sound.volume = 0;
		sound.pan = 0;

		sound.next = activeSoundList;
		activeSoundList = sound;

		return sound;
	}

	private void destroySound(ref MixerSound sound) @safe {
		for (MixerSound** currentSound = &activeSoundList; *currentSound != null; currentSound = &(*currentSound).next) {
			if (**currentSound == sound) {
				*currentSound = sound.next;
				break;
			}
		}
	}

	private void mixSounds(scope int[] stream) @safe nothrow {
		for (MixerSound* sound = activeSoundList; sound != null; sound = sound.next) {
			if (sound.playing) {
				int[] streamPointer = stream;

				for (size_t framesDone = 0; framesDone < stream.length / 2; ++framesDone) {
					// Perform linear interpolation
					const ubyte interpolationScale = sound.positionSubsample >> 8;

					const byte outputSample = cast(byte)((sound.samples[sound.position] * (0x100 - interpolationScale) + sound.samples[sound.position + 1] * interpolationScale) >> 8);

					// Mix, and apply volume

					streamPointer[0] += outputSample * sound.volumeL;
					streamPointer[1] += outputSample * sound.volumeR;
					streamPointer = streamPointer[2 .. $];

					// Increment sample
					const uint nextPositionSubsample = sound.positionSubsample + sound.advanceDelta / sampleRate;
					sound.position += nextPositionSubsample >> 16;
					sound.positionSubsample = nextPositionSubsample & 0xFFFF;

					// Stop or loop sample once it's reached its end
					if (sound.position >= (sound.samples.length - 1)) {
						if (sound.looping) {
							sound.position %= sound.samples.length - 1;
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
}

private struct Sample {
	ushort sampleRate;
	const(ubyte)[] data;
	short volume;
	int pan;
	void changeVolume(uint volume) @safe {
		this.volume = cast(short)volume;
	}
	void changePan(int pan) @safe {
		this.pan = pan;
	}
}

private struct WAVFile {
	align(1):
	char[4] chunkID;
	uint chunkSize;
	char[4] chunkFormat;
	char[4] subchunkID;
	uint subchunkSize;
	ushort formatTag;
	ushort numChannels;
	uint numSamplesPerSec;
	uint numAvgBytesPerSec;
	ushort numBlockAlign;
	ushort bitsPerSample;
	ushort cbSize;
	char[4] factchunk2ID;
	uint factchunk2Size;
	ubyte[4] factData;
	char[4] subchunk2ID;
	uint subchunk2Size;
	ubyte[0] data;
}

private immutable wavBASS1 = cast(immutable(ubyte)[])import("BASS1.wav");
private immutable wavBASS2 = cast(immutable(ubyte)[])import("BASS2.wav");
private immutable wavHAT1 = cast(immutable(ubyte)[])import("HAT1.wav");
private immutable wavHAT2 = cast(immutable(ubyte)[])import("HAT2.wav");
private immutable wavSNARE1 = cast(immutable(ubyte)[])import("SNARE1.wav");
private immutable wavSYMBAL1 = cast(immutable(ubyte)[])import("SYMBAL1.wav");

private struct MixerSound {
	byte[] samples;
	size_t position;
	ushort positionSubsample;
	uint advanceDelta;
	bool playing;
	bool looping;
	short globalVolume;
	short panL;
	short panR;
	short volumeL;
	short volumeR;

	MixerSound* next;
	void pan(int val) @safe nothrow {
		panL = MillibelToScale(-val);
		panR = MillibelToScale(val);

		volumeL = cast(short)((panL * globalVolume) >> 8);
		volumeR = cast(short)((panR * globalVolume) >> 8);
	}
	void volume(short val) @safe nothrow {
		globalVolume = MillibelToScale(val);

		volumeL = cast(short)((panL * globalVolume) >> 8);
		volumeR = cast(short)((panR * globalVolume) >> 8);
	}
	void frequency(uint val) @safe {
		advanceDelta = val << 16;
	}
	void play(bool loop) @safe nothrow {
		playing = true;
		looping = loop;

		samples[$ - 1] = loop ? samples[0] : 0;

	}
	void stop() @safe nothrow {
		playing = false;
	}
	void seek(size_t position) @safe nothrow {
		this.position = position;
		positionSubsample = 0;
	}
}

private ushort MillibelToScale(int volume) @safe pure @nogc nothrow {
	// Volume is in hundredths of a decibel, from 0 to -10000
	volume = clamp(volume, -10000, 0);
	return cast(ushort)(pow(10.0, volume / 2000.0) * 256.0);
}
