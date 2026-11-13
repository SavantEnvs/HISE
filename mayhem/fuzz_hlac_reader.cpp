// Fuzzes the HLAC (HISE lossless audio codec) reader: header parsing, then block decoding at the
// start of the stream and after a seek, once per target data type.
#include <JuceHeader.h>

#include <cstdint>
#include <memory>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
	hlac::HiseLosslessAudioFormat format;

	std::unique_ptr<AudioFormatReader> reader(
		format.createReaderFor(new MemoryInputStream(data, size, false), true));

	if (reader == nullptr || reader->numChannels == 0 || reader->numChannels > 2)
		return 0;

	auto* hlacReader = dynamic_cast<hlac::HiseLosslessAudioFormatReader*>(reader.get());

	if (hlacReader == nullptr)
		return 0;

	// The decoder reads in blocks of COMPRESSION_BLOCK_SIZE samples; a couple of blocks plus an
	// unaligned tail covers the cycle-header, diff and normalisation paths.
	const int numToRead = (int)jmin<int64>(reader->lengthInSamples, 2 * COMPRESSION_BLOCK_SIZE + 123);

	if (numToRead <= 0)
		return 0;

	AudioBuffer<float> buffer((int)reader->numChannels, numToRead);

	// HlacReaderCommon::usesFloatingPointData is only initialised by setTargetAudioDataType(), which every
	// real caller (the HISE sample loader) invokes before reading, so each type is set explicitly.
	for (auto type : { AudioDataConverters::float32LE, AudioDataConverters::int16LE })
	{
		hlacReader->setTargetAudioDataType(type);

		reader->read(&buffer, 0, numToRead, 0, true, true);

		// Seeking goes through the header's block offset table.
		if (reader->lengthInSamples > COMPRESSION_BLOCK_SIZE)
		{
			const int64 blockIndex = (size > 8 ? data[8] : 0) % (reader->lengthInSamples / COMPRESSION_BLOCK_SIZE);
			reader->read(&buffer, 0, jmin(numToRead, 777), blockIndex * COMPRESSION_BLOCK_SIZE, true, true);
		}
	}

	return 0;
}
