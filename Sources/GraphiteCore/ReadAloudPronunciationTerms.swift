import Foundation

/// The built-in terms, chosen from the most frequent technical words in the owner's notes
/// (VLSI, computer architecture, digital and analog circuits at ETH and EPFL; mined on
/// 2026-10-12 from 1,242 notes, read only) and said the way an engineer says them. A word
/// without a vowel that is not listed ("PLL", "FSM", "JSSC") is spelled by rule.
extension ReadAloudPronunciations {
    private typealias Entry = (term: String, pronunciation: Pronunciation)

    /// Said as a word, written as it sounds.
    private static func said(_ term: String, _ say: String) -> Entry { (term, Pronunciation(say: say)) }
    /// Said letter by letter, although it contains a vowel a voice might pronounce.
    private static func spelled(_ term: String) -> Entry {
        (term, Pronunciation(say: term.filter { character in character.isLetter || character.isNumber }.map(String.init).joined(separator: " ")))
    }
    /// Said as what it stands for; listed in Settings so the person can choose letters instead.
    private static func expanded(_ term: String, _ say: String, context: [String] = []) -> Entry {
        (term, Pronunciation(say: say, isExpansion: true, contextWords: context))
    }

    public static let standard = ReadAloudPronunciations(terms: Dictionary(uniqueKeysWithValues: standardEntries.map { entry in
        (entry.term, entry.pronunciation)
    }))

    private static let standardEntries: [Entry] = [
        // Memory
        said("RAM", "ram"), said("ROM", "rom"), said("DRAM", "dee ram"), said("SRAM", "ess ram"), said("SDRAM", "ess dee ram"),
        said("VRAM", "vee ram"), said("eDRAM", "ee dee ram"), said("ReRAM", "ree ram"), said("FeRAM", "fee ram"),
        said("MRAM", "em ram"), said("NVRAM", "N V ram"), said("PCM", "P C M"), said("EEPROM", "double E prom"),
        said("EPROM", "E prom"), said("PROM", "prom"), said("DIMM", "dim"), said("SIMM", "sim"), spelled("HBM"),
        said("HBM2", "H B M 2"), spelled("DDR"), said("DDR3", "D D R 3"), said("DDR4", "D D R 4"), said("DDR5", "D D R 5"),
        said("LPDDR", "L P D D R"), said("RowHammer", "row hammer"), said("RowPress", "row press"),
        said("ColumnDisturb", "column disturb"), said("RowClone", "row clone"), said("BlockHammer", "block hammer"),
        said("PuDHammer", "P U D hammer"), said("SoftMC", "soft M C"), said("pLUTo", "pluto"), said("PiDRAM", "pie dee ram"),
        said("PipeDRAM", "pipe dee ram"), said("TRR", "T R R"), said("PRAC", "prack"), said("ECC", "E C C"),
        said("NUMA", "noo-ma"), spelled("TLB"), said("ROB", "R O B"), said("CAM", "cam"), said("FIFO", "fife-oh"),
        said("LIFO", "life-oh"), said("MSHR", "M S H R"), said("SSD", "S S D"), said("HDD", "H D D"),
        // Processing in memory and accelerators
        said("PIM", "pim"), said("PUM", "pum"), said("PUD", "P U D"), said("PuD", "P U D"), said("UPMEM", "up mem"),
        said("DPU", "D P U"), said("SIMD", "sim dee"), said("MIMD", "mim dee"), said("SISD", "sis dee"), said("MISD", "mis dee"),
        said("SIMT", "sim tee"), said("SIMDRAM", "sim dee ram"), said("MIMDRAM", "mim dee ram"), said("SimplePIM", "simple pim"),
        said("LazyPIM", "lazy pim"), said("GPGPU", "G P G P U"), said("CUDA", "cooda"), said("TPU", "T P U"), said("NPU", "N P U"),
        // Processors and architecture
        spelled("CPU"), spelled("GPU"), spelled("ALU"), spelled("FPU"), spelled("MMU"), spelled("MCU"), spelled("MPU"),
        spelled("ISA"), said("RISC", "risk"), said("CISC", "sisk"), said("RISC-V", "risk five"), said("MIPS", "mips"),
        said("ARM", "arm"), said("x86", "x eighty-six"), said("x86-64", "x eighty-six sixty-four"), said("VLIW", "V L I W"),
        spelled("ILP"), spelled("CPI"), spelled("IPC"), spelled("PC"), spelled("IR"), spelled("SP"), spelled("OS"),
        said("SoC", "S O C"), said("NoC", "N O C"), said("IoT", "I O T"), said("AMBA", "amba"), said("AXI", "axi"),
        said("AXI4", "axi 4"), spelled("AHB"), spelled("APB"), said("UART", "you-art"), spelled("SPI"), expanded("I2C", "I squared C"),
        said("GPIO", "G P I O"), said("JTAG", "jay-tag"), spelled("DMA"), spelled("USB"), spelled("PCIe"), said("PCI", "P C I"),
        said("TrustZone", "trust zone"), said("PowerPC", "power P C"), expanded("BusRd", "bus read"), expanded("BusRdX", "bus read exclusive"),
        expanded("BusWr", "bus write"), expanded("PrRd", "processor read"), expanded("PrWr", "processor write"), said("MESI", "messy"),
        said("MOESI", "mo-ee-see"), spelled("API"), spelled("IO"), said("I/O", "I O"), spelled("UI"), said("GUI", "gooey"),
        said("ASCII", "askee"), spelled("AI"), spelled("ML"), spelled("LLM"), said("ChatGPT", "chat G P T"),
        // Devices and technology
        said("CMOS", "see moss"), said("NMOS", "en moss"), said("PMOS", "pee moss"), said("nMOS", "en moss"),
        said("pMOS", "pee moss"), said("MOS", "moss"), said("MOSFET", "moss fet"), said("FET", "fet"), said("FinFET", "fin fet"),
        said("FinFETs", "fin fets"), said("FeFET", "fee fet"), said("BiCMOS", "bye see moss"), said("JFET", "jay fet"),
        said("MOSIS", "moe-sis"), spelled("BJT"), spelled("NPN"), spelled("PNP"), spelled("IGBT"), said("SOI", "S O I"),
        said("DIBL", "dibble"), spelled("TSMC"), expanded("SiC", "silicon carbide"), expanded("GaAs", "gallium arsenide"),
        expanded("GaN", "gallium nitride"), expanded("SiGe", "silicon germanium"), expanded("SiO2", "silicon dioxide"), said("LED", "L E D"),
        said("ESD", "E S D"), said("TTL", "T T L"), said("ECL", "E C L"), said("VTC", "V T C"), expanded("FO4", "fan-out of 4"),
        // Logic and design
        said("NAND", "nand"), said("NOR", "nor"), said("XOR", "ex-or"), said("XNOR", "ex-nor"), said("MUX", "mux"),
        said("DEMUX", "dee-mux"), spelled("FSM"), said("FSMD", "F S M D"), said("ASMD", "A S M D"), said("ASM", "A S M"),
        expanded("LUT", "look-up table"), expanded("DFF", "D flip-flop"),
        expanded("FF", "flip-flop", context: ["clock", "register", "latch", "flip", "setup", "hold", "edge", "sequential", "d ff", "dff"]),
        said("LFSR", "L F S R"), spelled("MSB"), spelled("LSB"), said("ROBDD", "R O B D D"), said("OBDD", "O B D D"),
        said("BDD", "B D D"), said("PLA", "P L A"), said("PAL", "pal"), said("GAL", "gal"), said("CPLD", "C P L D"),
        spelled("FPGA"), said("ASIC", "ay-sick"), spelled("VLSI"), said("VHDL", "V H D L"), said("VHDL-87", "V H D L 87"),
        spelled("HDL"), spelled("RTL"), spelled("HLS"), said("SystemVerilog", "system verilog"), said("SystemC", "system C"),
        said("SPICE", "spice"), spelled("EDA"), spelled("CAD"), said("DFT", "D F T"), spelled("ODC"), spelled("STA"),
        said("ESPRESSO", "espresso"), said("DeMorgan", "de Morgan"), said("McCluskey", "mc-cluskey"), said("PUN", "P U N"),
        said("PDN", "P D N"), said("CVSL", "C V S L"), said("CPL", "C P L"), said("DPL", "D P L"), said("DCVSPG", "D C V S P G"),
        spelled("CLK"), expanded("RST", "reset"), expanded("GND", "ground"), said("VDD", "V D D"), said("VSS", "V S S"),
        said("VCC", "V C C"), said("VGS", "V G S"), said("VDS", "V D S"), expanded("VTH", "V threshold"), said("VT", "V T"),
        said("IDS", "I D S"), said("VCO", "V C O"), spelled("PLL"), spelled("DLL"), spelled("PFD"), spelled("CDR"),
        spelled("ADC"), spelled("DAC"), spelled("PWM"), spelled("PID"), spelled("RC"), spelled("RLC"), spelled("LC"),
        spelled("DC"), spelled("AC"), expanded("DC-DC", "D C to D C"), said("IC", "I C"), spelled("PCB"), said("RF", "R F"),
        // Signals and systems
        spelled("DSP"), spelled("FFT"), spelled("FIR"), spelled("IIR"), spelled("LTI"), spelled("SNR"),
        spelled("BER"), spelled("ISI"), said("ROC", "R O C"), spelled("AM"), spelled("FM"), said("QAM", "kwam"),
        said("OFDM", "O F D M"), said("LoRa", "lora"), said("ZigBee", "zig bee"), said("WiFi", "wifi"),
        // Organizations, venues, places
        said("IEEE", "I triple E"), said("ACM", "A C M"), said("ISCA", "iss-ka"), spelled("HPCA"), said("MICRO", "micro"),
        said("ISSCC", "I S S C C"), spelled("JSSC"), said("EPFL", "E P F L"), said("ETH", "E T H"), said("SAFARI", "safari"),
        said("IBM", "I B M"), said("AMD", "A M D"), said("JEDEC", "jed-eck"), said("MOOC", "mook"), said("arXiv", "archive"),
        said("PhD", "P H D"), said("LaTeX", "lay-tech"), said("GitHub", "git hub"), said("GitLab", "git lab"),
        said("MTBF", "M T B F"), said("MTTF", "M T T F"), spelled("IP"), spelled("ID"), said("MAC", "mack"),
        spelled("USA"), spelled("CSA"), spelled("CPA"), spelled("AVR"), spelled("CI"), spelled("LU"), spelled("PI")
    ]
}
