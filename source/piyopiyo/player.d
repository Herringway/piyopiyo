module piyopiyo.player;

import std.algorithm.comparison;
import std.experimental.logger;
import std.math;

import core.time;

import simplesoftermix.interpolation;
import simplesoftermix.mixer;

public import simplesoftermix.interpolation : InterpolationMethod;

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
	private size_t[int] loadedSamples;
	private uint sampleRate;
	private uint masterTimer;
	private Mixer mixer;
	public void initialize(uint sampleRate, InterpolationMethod interpolationMethod) @safe {
		mixer = Mixer(interpolationMethod, sampleRate);
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
							mixer.getSound(*sample).pan = (panTable[pan] - 256) * 10;
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
					mixer.getSound(loadedSamples[400 + (i * 24) + j]).volume = cast(short)((header.track[i].volume - volume - 300) * 8);
				}
			}

			//Set drum volume
			for (int i = 0; i < 24; i += 2) {
				mixer.getSound(loadedSamples[472 + i]).volume = cast(short)((header.percussionVolume - volume - 300) * 8);
				mixer.getSound(loadedSamples[473 + i]).volume = cast(short)((70 * header.percussionVolume / 100 - volume - 300) * 8);
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

	private bool makeSoundObject(scope byte[] wave, scope ubyte[] envelope, int octave, int dataSize, int no) @safe {
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
			loadedSamples[no + i] = mixer.createSound(22050, wp[0 .. dataSize]);
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
					mixer.getSound(*sample).stop();
					break;

				case SoundMode.play:
					mixer.getSound(*sample).stop();
					mixer.getSound(*sample).seek(0);
					mixer.getSound(*sample).play(false);
					break;

				case SoundMode.playLoop:
					mixer.getSound(*sample).play(true);
					break;
				default: break;
			}
		}
	}
	private size_t loadWav(const(ubyte)[] data) @safe {
		if (data == null) { //uh oh. no audio. use an empty sample
			return mixer.createSound(22050, (byte[]).init);
		}
		auto wav = (cast(const(WAVFile)[])(data)[0 .. WAVFile.sizeof])[0];
		return mixer.createSound(cast(ushort)wav.numSamplesPerSec, data[wav.data.offsetof .. wav.data.offsetof + wav.subchunk2Size]);
	}

	public void fillBuffer(scope short[2][] finalBuffer) @safe nothrow {
		if (masterTimer == 0) {
			mixer.mixSounds(finalBuffer);
		} else {
			uint framesDone = 0;
			finalBuffer[] = [0, 0];

			while (framesDone != finalBuffer.length) {
				static ulong updateTimer;

				if (updateTimer == 0) {
					updateTimer = masterTimer;
					update();
				}

				const ulong framesToDo = min(updateTimer, finalBuffer.length - framesDone);

				mixer.mixSounds(finalBuffer[framesDone .. framesDone + framesToDo]);

				framesDone += framesToDo;
				updateTimer -= framesToDo;
			}
		}
	}

	private void setMusicTimer(uint milliseconds) @safe {
		masterTimer = (milliseconds * sampleRate) / 1000;
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
