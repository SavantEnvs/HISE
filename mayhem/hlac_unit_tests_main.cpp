// Console runner for upstream's HLAC unit tests (tools/hlac_tool/Source/HlacTests.cpp). Prints one
// `TEST PASS|FAIL <suite> / <case>` line per test case.
//
// Upstream's own CodecTest::runTest() has a debugging `return;` after its first case, and the monolithic
// FormatTest overflows a one-element Range<float> in its own test code (HlacTests.cpp:1916: readMaxLevels
// writes results[1] for stereo). So the cases are driven from here through CodecTest's public methods
// instead of through UnitTestRunner::runAllTests().
#include <JuceHeader.h>

#include "../tools/hlac_tool/Source/HlacTests.h"

#include <cstdio>

struct FullCodecTest : public CodecTest
{
	void runTest() override
	{
		testIntegerBuffers();
		testCopyWithNormalisation();
		testHiseSampleBuffer();
		testNormalisation();

		for (int i = 0; i < (int)SignalType::numSignalTypes; i++)
		{
			beginTest("Testing codecs for signal " + getNameForSignal((SignalType)i));

			for (int j = 0; j < (int)Option::numCompressorOptions; j++)
			{
				testCodec((SignalType)i, (Option)j, false);
				testCodec((SignalType)i, (Option)j, true);
			}
		}
	}
};

int main()
{
	FullCodecTest codec;
	BitCompressors::UnitTests bits;

	UnitTestRunner runner;
	runner.setAssertOnFailure(false);

	Array<UnitTest*> selected;
	selected.add(&bits);
	selected.add(&codec);
	runner.runTests(selected);

	int numFailed = 0;

	for (int i = 0; i < runner.getNumResults(); ++i)
	{
		auto* r = runner.getResult(i);
		const bool ok = r->failures == 0 && r->passes > 0;
		numFailed += ok ? 0 : 1;
		std::printf("TEST %s %s / %s (passes=%d failures=%d)\n", ok ? "PASS" : "FAIL",
					r->unitTestName.toRawUTF8(), r->subcategoryName.toRawUTF8(), r->passes, r->failures);
	}

	std::printf("HLAC_UNIT_TESTS cases=%d failed=%d\n", runner.getNumResults(), numFailed);
	return numFailed == 0 ? 0 : 1;
}
