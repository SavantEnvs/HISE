// Fuzzes HISE's zstd decompression of user-supplied preset data: ZCompressor::expand() into a
// MemoryBlock, a String and a ValueTree (the preset/user-preset path), and expandInplace().
#include <juce_core/juce_core.h>
#include <juce_data_structures/juce_data_structures.h>
#include "../hi_zstd/hi_zstd.h"

#include <cstdint>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	const juce::MemoryBlock compressed(data, size);

	// A fresh decompress-only compressor per call: no dictionary provider and no context state is shared
	// between inputs (HISE builds a new ZCompressor for each preset it extracts).
	{
		zstd::ZDefaultCompressor decompressor(zstd::ZCompressorBase::DecompressOnly);
		juce::MemoryBlock raw;
		decompressor.expand(compressed, raw);
	}
	{
		zstd::ZDefaultCompressor decompressor(zstd::ZCompressorBase::DecompressOnly);
		juce::String text;
		decompressor.expand(compressed, text);
	}
	{
		zstd::ZDefaultCompressor decompressor(zstd::ZCompressorBase::DecompressOnly);
		juce::ValueTree tree;
		decompressor.expand(compressed, tree);
	}
	{
		zstd::ZDefaultCompressor decompressor(zstd::ZCompressorBase::DecompressOnly);
		juce::MemoryBlock inplace(compressed);
		decompressor.expandInplace(inplace);
	}

	return 0;
}
