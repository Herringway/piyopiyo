import piyopiyo;

import std.algorithm.comparison;
import std.experimental.logger;
import std.exception;
import std.file;
import std.format;
import std.getopt;
import std.path;
import std.stdio;
import std.string;
import std.utf;
import bindbc.sdl : SDL_AudioCallback, SDL_AudioDeviceID;

bool initAudio(SDL_AudioCallback fun, ubyte channels, uint sampleRate, void* userdata = null) @trusted {
	SDL_AudioDeviceID dev;
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
	sampleFunc(*cast(PiyoPiyo*)user, cast(short[2][])(buf[0 .. bufSize]));
}
void sampleFunc(ref PiyoPiyo piyo, short[2][] buf) nothrow @safe {
	piyo.fillBuffer(buf);
}

int main(string[] args) {
	enum channels = 2;
	ushort sampleRate = 48000;
	bool verbose;
	InterpolationMethod interpolation;
	auto help = getopt(args,
		"i|interpolation", "Sets interpolation (none, linear, cubic)", &interpolation,
		"v|verbose", "Print more messages", &verbose,
		"s|samplerate", "Sample rate (default 44100hz)", &sampleRate,
	);
	if (help.helpWanted || args.length < 2) {
		defaultGetoptPrinter("Organya player", help.options);
		return 1;
	}

	if (args.length < 2) {
		return 1;
	}
	if (verbose) {
		(cast()sharedLog).logLevel = LogLevel.trace;
	}

	auto file = cast(ubyte[])read(args[1]);

	auto piyo = PiyoPiyo();
	trace("Initializing piyopiyo");
	piyo.initialize(sampleRate, interpolation);

	trace("Loading piyopiyo file");
	// Load file
	piyo.loadMusic(file);

	// Prepare to play music
	if (!initAudio(&_sampling_func, channels, sampleRate, &piyo)) {
		return 1;
	}
	trace("SDL audio init success");

	piyo.play();

	writeln("Press enter to exit");
	readln();

	return 0;
}
