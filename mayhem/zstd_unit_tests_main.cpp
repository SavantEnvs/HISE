// Console runner for upstream's zstd unit tests (hi_zstd/hi_zstd/ZstdUnitTests.cpp, "Zstd Unit Tests"):
// compress/expand round trips for ValueTree, String and File, asserting the decompressed value equals the
// source. Prints one `TEST PASS|FAIL <suite> / <case>` line per test case.
#include <juce_core/juce_core.h>
#include <juce_data_structures/juce_data_structures.h>
#include "../hi_zstd/hi_zstd.h"

#include <cstdio>

int main()
{
	juce::UnitTestRunner runner;
	runner.setAssertOnFailure(false);
	runner.runAllTests();

	int numFailed = 0;

	for (int i = 0; i < runner.getNumResults(); ++i)
	{
		auto* r = runner.getResult(i);
		const bool ok = r->failures == 0 && r->passes > 0;
		numFailed += ok ? 0 : 1;
		std::printf("TEST %s %s / %s (passes=%d failures=%d)\n", ok ? "PASS" : "FAIL",
					r->unitTestName.toRawUTF8(), r->subcategoryName.toRawUTF8(), r->passes, r->failures);
	}

	std::printf("ZSTD_UNIT_TESTS cases=%d failed=%d\n", runner.getNumResults(), numFailed);
	return numFailed == 0 ? 0 : 1;
}
