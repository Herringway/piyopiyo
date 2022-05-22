module pixel.piyopiyo;

import smixer;

import std.algorithm.comparison;
import std.experimental.logger;

import core.time;
import core.atomic;

immutable WAVFile format_tbl2 = {"RIFF", 0, "WAVE", "fmt ", 16, 1, 1, 22050, 22050, 1, 8, 0, "data"};
immutable int[12] freq_tbl = [ 1551, 1652, 1747, 1848, 1955, 2074, 2205, 2324, 2461, 2616, 2770, 2938 ];

enum SoundMode {
	PLAY_LOOP = -1,
	STOP = 0,
	PLAY = 1
}

struct PIYOPIYO_CONTROL {
	char mode;
	string track;
	string prev_track;
	short volume;
}

enum MAX_RECORD = 1000;

struct PIYOPIYO_TRACKHEADER {
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
static assert(PIYOPIYO_TRACKHEADER.sizeof == 0x154);

struct PIYOPIYO_HEADER {
	char[3] magic;
	bool writable;
	uint p_track1;
	uint wait;
	int repeat_x;
	int end_x;
	int records;

	//Track headers
	PIYOPIYO_TRACKHEADER[3] track;
	uint percussion_volume;
}
static assert(PIYOPIYO_HEADER.sizeof == 0x418);

struct PIYOPIYO {
	//Loaded header
	PIYOPIYO_HEADER header;

	//Playback state
	bool playing;
	int position;
	MonoTime tick;
	uint[MAX_RECORD][4] record;
	bool initialized;
	int volume;
	bool fading;
	Mixer_Sound*[int] loadedSamples;
	SoftwareMixer backend;
	bool initialize() @safe {
		//Load drums
		if (!(InitSoundObject(loadWav(wavBASS1), 472) &&
		InitSoundObject(loadWav(wavBASS1), 473) &&
		InitSoundObject(loadWav(wavBASS2), 474) &&
		InitSoundObject(loadWav(wavBASS2), 475) &&
		InitSoundObject(loadWav(wavSNARE1), 476) &&
		InitSoundObject(loadWav(wavSNARE1), 477) &&
		InitSoundObject(loadWav(wavSNARE1), 478) &&
		InitSoundObject(loadWav(wavSNARE1), 479) &&
		InitSoundObject(loadWav(wavHAT1), 480) &&
		InitSoundObject(loadWav(wavHAT1), 481) &&
		InitSoundObject(loadWav(wavHAT2), 482) &&
		InitSoundObject(loadWav(wavHAT2), 483) &&
		InitSoundObject(loadWav(wavSYMBAL1), 484) &&
		InitSoundObject(loadWav(wavSYMBAL1), 485) &&
		InitSoundObject(loadWav(wavSYMBAL1), 486) &&
		InitSoundObject(loadWav(wavSYMBAL1), 487) &&
		InitSoundObject(loadWav(wavSYMBAL1), 488) &&
		InitSoundObject(loadWav(wavSYMBAL1), 489) &&
		InitSoundObject(loadWav(wavSYMBAL1), 490) &&
		InitSoundObject(loadWav(wavSYMBAL1), 491) &&
		InitSoundObject(loadWav(wavSYMBAL1), 492) &&
		InitSoundObject(loadWav(wavSYMBAL1), 493) &&
		InitSoundObject(loadWav(wavSYMBAL1), 494) &&
		InitSoundObject(loadWav(wavSYMBAL1), 495))) {
			return false;
		}
		initialized = true;

		backend.setMusicCallback(&PiyoPiyoProc);
		return true;
	}
	bool InitSoundObject(Mixer_Sound* sample, int number) @safe {
		loadedSamples[number] = sample;
		return true;
	}
	bool ReadPiyoPiyo(const ubyte[] data) @safe {
		//Fail if PiyoPiyo hasn't been initialised
		if (initialized == false)
			return false;

		//Read data
		header = (cast(const(PIYOPIYO_HEADER[]))(data[0 .. PIYOPIYO_HEADER.sizeof]))[0];
		record[0][0 .. header.records] = cast(const(uint[]))(data[PIYOPIYO_HEADER.sizeof + header.records * 0 * uint.sizeof .. PIYOPIYO_HEADER.sizeof + header.records * 1 * uint.sizeof]);
		record[1][0 .. header.records] = cast(const(uint[]))(data[PIYOPIYO_HEADER.sizeof + header.records * 1 * uint.sizeof .. PIYOPIYO_HEADER.sizeof + header.records * 2 * uint.sizeof]);
		record[2][0 .. header.records] = cast(const(uint[]))(data[PIYOPIYO_HEADER.sizeof + header.records * 2 * uint.sizeof .. PIYOPIYO_HEADER.sizeof + header.records * 3 * uint.sizeof]);
		record[3][0 .. header.records] = cast(const(uint[]))(data[PIYOPIYO_HEADER.sizeof + header.records * 3 * uint.sizeof .. PIYOPIYO_HEADER.sizeof + header.records * 4 * uint.sizeof]);
		position = -1;
		fading = false;
		return true;
	}
	void PiyoPiyoProc() @safe nothrow {
		static immutable int[8] pan_tbl = [
			0, 96, 180, 224, 256, 288, 332, 420
		];

		//Check if next step should be played
		if (initialized && playing && MonoTime.currTime() > (cast(MonoTime)tick + header.wait.msecs)) {
			if (fading) {
				if (volume < 250) {
					ChangePiyoPiyoVolume(volume + 1);
				} else {
					fading = false;
					playing = false;
				}
			}
			//Check if position passes loop point
			if (position++ > (header.end_x - 1) || position > (header.records - 1)) {
				position = header.repeat_x;
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
							(*sample).pan = (pan_tbl[pan] - 256) * 10;
						}
					}
				}

				//Play notes
				for (int j = 0; j < 24; j++) {
					if (record & 1) {
						PlaySoundObject(400 + (i * 24) + j, 1);
					}
					record >>= 1;
				}
			}

			//Remember previous tick
			tick = MonoTime.currTime();
		}
	}
	void MakePiyoPiyoSoundObjects() @safe {
		//Make sure PiyoPiyo has been initialised
		if (initialized) {
			//Setup each melody track
			for (int i = 0; i < 3; i++) {
				//Get octave
				int octave = 1 << header.track[i].octave;

				//Release previous objects
				for (int j = 0; j < 24; j++) {
					ReleaseSoundObject(400 + (i * 24) + j);
				}

				//Make new objects
				MakePiyoPiyoSoundObject(
					header.track[i].wave[],
					header.track[i].envelope[],
					octave,
					header.track[i].length,
					400 + (24 * i));
			}
			ChangePiyoPiyoVolume(0);
		}
	}

	void ChangePiyoPiyoVolume(int volume) @safe nothrow {
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
				loadedSamples[472 + i].volume = cast(short)((header.percussion_volume - volume - 300) * 8);
				loadedSamples[473 + i].volume = cast(short)((70 * header.percussion_volume / 100 - volume - 300) * 8);
			}
		}
	}
	void PlayPiyoPiyo() @safe {
		playing = true;
		backend.setMusicTimer(20);
	}

	void StopPiyoPiyo() @safe {
		playing = false;
		backend.setMusicTimer(0);
	}

	bool LoadPiyoPiyo(const ubyte[] data) @safe {
		ReadPiyoPiyo(data);
		MakePiyoPiyoSoundObjects();
		return true;
	}

	void SetPiyoPiyoFadeout() @safe {
		fading = true;
	}

	void SetPiyoPiyoPosition(uint position) @safe {
		position = position;
	}
	uint GetPiyoPiyoPosition() @safe {
		return position;
	}

	bool MakePiyoPiyoSoundObject(byte[] wave, ubyte[] envelope, int octave, int data_size, int no) @safe {
		bool result;
		int i;

		//Write sound data
		ubyte[] wp = new ubyte[](data_size);

		for (i = 0; i < 24; i++) {
			//Construct waveform
			int wp_sub = 0;
			int envelope_i = 0;

			for (int j = 0; j < data_size; j++) {
				//Get sample
				int sample = wave[cast(ubyte)(wp_sub / 256)];
				envelope_i = (j << 6) / data_size;
				sample = sample * envelope[envelope_i] / 128;

				//Set sample
				wp[j] = cast(ubyte)(sample + 0x80);

				//Increase sub-pos
				int freq;
				if (i < 12) {
					freq = octave * freq_tbl[i] / 16;
				} else {
					freq = octave * freq_tbl[i - 12] / 8;
				}
				wp_sub += freq;
			}
			loadedSamples[no + i] = backend.createSound(22050, wp);
		}

		//Check if there was an error and free wave buffer
		if (i == 24) {
			result = true;
		}
		return result;
	}
	void PlaySoundObject(int no, int mode) @safe nothrow {
		if (auto sample = no in loadedSamples) {
			switch (mode) {
				case SoundMode.STOP:
					backend.stop(**sample);
					break;

				case SoundMode.PLAY:
					backend.stop(**sample);
					backend.seek(**sample, 0);
					backend.play(**sample, SoundPlayFlags.normal);
					break;

				case SoundMode.PLAY_LOOP:
					backend.play(**sample, SoundPlayFlags.looping);
					break;
				default: break;
			}
		}
	}
	void ReleaseSoundObject(int no) @safe {
		if (auto sample = no in loadedSamples) {
			backend.destroySound(**sample);
		}
	}
	Mixer_Sound* loadWav(const(ubyte)[] data) @safe {
		if (data == null) { //uh oh. no audio. use an empty sample
			return backend.createSound(22050, []);
		}
		auto wav = (cast(const(WAVFile)[])(data)[0 .. WAVFile.sizeof])[0];
		return backend.createSound(cast(ushort)wav.numSamplesPerSec, data[wav.data.offsetof .. wav.data.offsetof + wav.subchunk2Size]);
	}
	void fillBuffer(scope short[] finalBuffer) nothrow @safe {
		int[0x800 * 2] buffer;
		backend.mixSoundsAndUpdateMusic(buffer[0 .. finalBuffer.length]);
		for (size_t i = 0; i < finalBuffer.length; ++i) {
			finalBuffer[i] = cast(short)clamp(buffer[i], short.min, short.max);
		}
	}
}



struct Sample {
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

struct WAVFile {
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
//PIYOPIYO gPiyoPiyo;

immutable wavBASS1 = cast(immutable(ubyte)[])import("BASS1.wav");
immutable wavBASS2 = cast(immutable(ubyte)[])import("BASS2.wav");
immutable wavHAT1 = cast(immutable(ubyte)[])import("HAT1.wav");
immutable wavHAT2 = cast(immutable(ubyte)[])import("HAT2.wav");
immutable wavSNARE1 = cast(immutable(ubyte)[])import("SNARE1.wav");
immutable wavSYMBAL1 = cast(immutable(ubyte)[])import("SYMBAL1.wav");
