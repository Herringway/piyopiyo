import piyopiyo;

import std.algorithm.comparison;
import std.experimental.logger;
import std.exception;
import std.file;
import std.format;
import std.path;
import std.stdio;
import std.string;
import std.utf;
import bindbc.sdl : SDL_AudioCallback, SDL_AudioDeviceID;

enum _CHANNEL_NUM = 2;
enum _SAMPLE_PER_SECOND = 48000;

__gshared SDL_AudioDeviceID dev;

bool initAudio(SDL_AudioCallback fun, ubyte channels, uint sampleRate, void* userdata = null) {
	import bindbc.sdl;

	enforce(loadSDL() == sdlSupport);
	if (SDL_Init(SDL_INIT_AUDIO) != 0) {
		criticalf("SDL init failed: %s", SDL_GetError().fromStringz);
		return false;
	}
	SDL_AudioSpec want, have;
	want.freq = sampleRate;
	want.format = SDL_AudioFormat.AUDIO_S16;
	want.channels = channels;
	want.samples = 512;
	want.callback = fun;
	want.userdata = userdata;
	dev = SDL_OpenAudioDevice(null, 0, &want, &have, 0);
	if (dev == 0) {
		criticalf("SDL_OpenAudioDevice failed: %s", SDL_GetError().fromStringz);
		return false;
	}
	SDL_PauseAudioDevice(dev, 0);
	return true;
}

extern (C) void _sampling_func(void* user, ubyte* buf, int bufSize) nothrow {
	PIYOPIYO* piyo = cast(PIYOPIYO*) user;
	piyo.fillBuffer(cast(short[])(buf[0 .. bufSize]));
}

int main(string[] args) {
	if (args.length < 2) {
		return 1;
	}
	sharedLog = new FileLogger(stdout, LogLevel.trace);

	auto filePath = args[1];
	auto file = cast(ubyte[])read(args[1]);

	// pxtone initialization
	auto piyo = PIYOPIYO();
	trace("Initializing PIYOPIYO");
	piyo.initialize();
	//trace("Setting quality");
	//piyo.set_destination_quality(_CHANNEL_NUM, _SAMPLE_PER_SECOND);

	trace("Loading piyopiyo file");
	// Load file
	piyo.LoadPiyoPiyo(file);

	// Prepare to play music
	if (!initAudio(&_sampling_func, _CHANNEL_NUM, _SAMPLE_PER_SECOND, &piyo)) {
		return 1;
	}
	trace("SDL audio init success");

	piyo.PlayPiyoPiyo();

	writeln("Press enter to exit");
	readln();

	return 0;
}
