import Testing
@testable import RippleToHideCore

@Test func maskReplacesAsciiDigitsAndKeepsTheRest() {
    #expect(BalanceMask.mask("$4,820.16") == "$•,•••.••")
    #expect(BalanceMask.mask("1 284,50 €") == "• •••,•• €")
    #expect(BalanceMask.mask("-£42") == "-£••")
    #expect(BalanceMask.mask("USD 12") == "USD ••")
    #expect(BalanceMask.mask("0") == "•")
    #expect(BalanceMask.mask("") == "")
    #expect(BalanceMask.mask("hello") == "hello")
    #expect(BalanceMask.mask("—") == "—")
    // Non-ASCII digits are left alone so a locale's own numerals are not guessed at.
    #expect(BalanceMask.mask("٤٢") == "٤٢")
}

@Test func maskedStringKeepsTheOriginalLength() {
    let samples = ["$4,820.16", "€ 42.00", "-$0.50", "1 284,50 €", ""]
    for sample in samples {
        #expect(BalanceMask.mask(sample).count == sample.count)
    }
}

@Test func displaySwitchesOnTheHiddenFlag() {
    #expect(BalanceMask.display("$4,820.16", hidden: false) == "$4,820.16")
    #expect(BalanceMask.display("$4,820.16", hidden: true) == "$•,•••.••")
}
