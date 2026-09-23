# Digital Pedalboard: Offline SystemVerilog RTL & MATLAB Audio DSP System

An offline, laptop-only digital effects pedalboard. The actual audio signal processing algorithms are implemented in **synthesizable SystemVerilog RTL** and simulated using **Icarus Verilog**, with **MATLAB** serving as the front-end audio manager, PCM converter, simulation runner, and waveform verification interface.

---

## 1. Project Objective

The goal of this project is to model, implement, and verify a complete digital guitar multi-effects pedalboard in hardware-description language (SystemVerilog) on a standard personal computer without requiring an FPGA development board or external audio interfaces.

Real WAV audio is processed offline through an RTL-synthesizable effects chain, proving that the digital signal processing algorithms and finite-precision fixed-point math will function identically when eventually flashed onto physical FPGA silicon.

---

## 2. System Architecture

The project operates as a closed-loop offline co-simulation pipeline:

```
                    AUDIO.wav (44.1 kHz, 16-bit PCM)
                                       │
                                       ▼
                             MATLAB/prepare_audio.m
                  (Stereo->Mono, Resampling, Q15 PCM Conversion)
                                       │
                                       ▼
                            MATLAB/input_samples.txt
                                       │
                                       ▼
                          TESTBENCH/tb_pedalboard.sv
                                       │
                                       ▼
                            RTL/pedalboard_top.sv
  ┌────────────────────────────────────┴────────────────────────────────────┐
  │                                                                         │
  │   [0] Pitch Shift         (RTL/pitch_shift.sv - Rectifier / Divider)    │
  │          │                                                              │
  │   [1] Auto-Wah            (RTL/wah.sv - Chamberlin SVF + Triangle LFO)  │
  │          │                                                              │
  │   [2] Distortion          (RTL/distortion.sv - Q8 Gain + Saturation)    │
  │          │                                                              │
  │   [3] Phaser              (RTL/phaser.sv - 4-Stage All-Pass + LFO)      │
  │          │                                                              │
  │   [4] Chorus              (RTL/chorus.sv - Modulated Delay Line)        │
  │          │                                                              │
  │   [5] Tremolo             (RTL/tremolo.sv - Q15 Amplitude Mod + LFO)    │
  │          │                                                              │
  │   [6] Delay / Echo        (RTL/delay_echo.sv - Circular Buffer + FB)    │
  │          │                                                              │
  │   [7] Reverb              (RTL/reverb.sv - Schroeder Comb + Allpass)    │
  │          │                                                              │
  │   [8] Looper              (RTL/looper.sv - Record/Playback Buffer Engine│
  │                                                                         │
  └────────────────────────────────────┬────────────────────────────────────┘
                                       │
                                       ▼
                           MATLAB/output_samples.txt
                                       │
                                       ▼
                           MATLAB/reconstruct_audio.m
                                       │
                                       ▼
                            AUDIO/output.wav
                                       │
                                       ▼
                           Laptop Speakers / Headphones
                                       │
                                       ▼
                           MATLAB/verify_effects.m
                    (Plots, RMS, Peaks, Clipping Bounds)
```

---

## 3. Why MATLAB is Being Used?

- **Audio File I/O**: Efficiently reads, normalizes, resamples, and writes standard audio containers (`.wav`) via `audioread` and `audiowrite`.
- **Automated Workflow Orchestrator**: Automatically generates simulation configuration headers (`sim_config.svh`), triggers the HDL compiler and simulator via system calls, and handles errors cleanly.
- **Verification & Visualization**: Analyzes input and output waveforms in the time domain and frequency domain (FFT magnitude spectra), checking numerical constraints such as clipping thresholds and bypass bit-exactness.
- **Audible Playback**: Plays the reconstructed audio directly through laptop speakers.

> [!NOTE]
> MATLAB does **NOT** compute the DSP effects. The actual audio effects are executed exclusively in SystemVerilog RTL by the Icarus Verilog simulation engine.

---

## 4. Why an HDL Simulator is Being Used?

- Enables hardware logic verification cycle-by-cycle without needing an expensive physical FPGA board or JTAG programmer.
- Models bit-accurate fixed-point registers, arithmetic saturation, overflow hazards, circular memory addressing, and pipeline latency.
- Discovers RTL syntax, timing, and boundary condition bugs before synthesis.

---

## 5. Why No FPGA or External hardware is needed?

In a physical hardware system, an audio codec (e.g. AC'97 or I2S chip such as Cirrus Logic CS4270 or Wolfson WM8731) is required to convert analog signals to digital bitstreams (ADC) and vice-versa (DAC).

In this **laptop-only offline RTL simulation**:
- The laptop's operating system and MATLAB already read digitized samples from `guitar.wav`.
- The HDL testbench feeds digital samples directly to `sample_in` alongside clock and `valid_in` strobes.
- Output samples are captured directly to disk (`output_samples.txt`) and reconstructed into `output.wav`.
- Eliminating the hardware codec interface simplifies testing while keeping the core DSP RTL 100% portable to any future hardware target.

---

## 6. Complete Data Conversion Process

### 6.1 WAV $\rightarrow$ PCM (`prepare_audio.m`)
1. Reads `guitar.wav` (any sample rate or channel count).
2. Converts stereo audio to mono: `y_mono = mean(y, 2)`.
3. Resamples to 44.1 kHz using linear or polyphase interpolation.
4. Trims duration to `MAX_SECONDS` (e.g. 3.0 seconds = 132,300 samples).
5. Normalizes amplitude to 0.90 (-1 dBFS peak).
6. Converts double values $[-1.0, +1.0]$ into signed 16-bit integers $[-32768, +32767]$ via `round(y * 32767.0)`.
7. Writes each integer to `MATLAB/input_samples.txt` separated by newline characters.

### 6.2 PCM $\rightarrow$ SystemVerilog (`tb_pedalboard.sv`)
1. The testbench opens `input_samples.txt` via `$fopen`.
2. Reads integer tokens sequentially using `$fscanf(in_file, "%d\n", sample_val)`.
3. Applies `valid_in <= 1'b1` and `sample_in <= sample_val[15:0]` synchronous to `clk`.
4. Streams samples through the 9-stage pipeline.

### 6.3 SystemVerilog $\rightarrow$ Output PCM (`tb_pedalboard.sv`)
1. The testbench monitors `valid_out` on every positive clock edge.
2. Whenever `valid_out` is high, it writes `$fdisplay(out_file, "%d", sample_out)` to `output_samples.txt`.
3. Flushes remaining pipeline stages after all inputs are delivered.

### 6.4 Output PCM $\rightarrow$ WAV (`reconstruct_audio.m`)
1. Reads `output_samples.txt` integer array.
2. Normalizes integers back to double floating-point: `y = double(pcm) / 32767.0`.
3. Clamps safely to $[-1.0, +1.0]$.
4. Writes `AUDIO/output.wav` with 16-bit resolution at 44.1 kHz.
5. Emits audio through laptop speakers via MATLAB `audioplayer` or `sound`.

---

## 7. RTL Audio Effects Specifications

### 1. Pitch / Octave (`RTL/pitch_shift.sv`)
Emulates classic analog guitar pedal octave circuits rather than high-latency studio FFT pitch shifters:
- **MODE 1 (Octave-Up)**: Emulates the full-wave rectifier circuit of classic pedals like the *Tycobrahe Octavia* and *Dan Armstrong Green Ringer*. Taking $|x[n]|$ folds negative half-cycles, mathematically doubling the fundamental frequency ($2f_0$). An integrated 1st-order DC-blocking highpass filter ($y[n] = x[n] - x[n-1] + 0.992 y[n-1]$) removes the resulting DC offset.
- **MODE 2 (Octave-Down)**: Emulates sub-octave divider pedals like the *BOSS OC-2*. A Schmitt-trigger zero-crossing detector toggles a T flip-flop on every complete audio cycle ($f_0 / 2$). Multiplying the input signal by the divider polarity alternates phase every cycle, generating a rich sub-octave tone that tracks player dynamics.

### 2. Auto-Wah (`RTL/wah.sv`)
Implements a Chamberlin State Variable Filter (SVF) swept across vocal formant frequencies:
- Difference equations:
  $$\text{lowpass}[n] = \text{lowpass}[n-1] + f \cdot \text{bandpass}[n-1]$$
  $$\text{highpass}[n] = x[n] - \text{lowpass}[n] - q \cdot \text{bandpass}[n-1]$$
  $$\text{bandpass}[n] = \text{bandpass}[n-1] + f \cdot \text{highpass}[n]$$
- Tuning coefficient $f$ is swept between $F_{min} \approx 380\text{ Hz}$ and $F_{max} \approx 2200\text{ Hz}$ by a smooth 24-bit triangle LFO (~1.5 Hz).
- Damping factor $q \approx 0.15$ sets a sharp vocal resonance ($Q \approx 6.6$).

### 3. Distortion (`RTL/distortion.sv`)

Models hard-clipping diode distortion (e.g. *ProCo Rat* / *BOSS DS-1*).

- **Fixed-point gain scaling:**

  `scaled = (x[n] × DRIVE_Q8) >> 8`

- **Hard clipping:**

  | Output | Condition |
  | :---: | :--- |
  | `+THRESHOLD` | `scaled > +THRESHOLD` |
  | `-THRESHOLD` | `scaled < -THRESHOLD` |
  | `scaled` | Otherwise |

- Employs **32-bit internal math** with strict saturation clamping to prevent signed two's complement overflow wrap-around.

### 4. Phaser (`RTL/phaser.sv`)
Implements a 4-stage all-pass ladder (modeling classic 4-stage phasers like the *MXR Phase 90*):
- Each stage uses the canonical 1st-order all-pass filter difference equation:
  $$y_s[n] = x_s[n-1] + a \cdot (x_s[n] - y_s[n-1])$$
- All-pass coefficient $a$ is modulated over $[-0.61, +0.61]$ by a slow triangle LFO (~0.5 Hz).
- Sweeps phase-cancellation notches across the frequency spectrum. A 25% negative feedback loop sharpens the notches.

### 5. Chorus (`RTL/chorus.sv`)
Implements analog bucket-brigade device (BBD) chorus:
- Circular delay buffer with a base delay of ~8 ms (350 samples).
- Modulated read pointer varied by $\pm 2.2\text{ ms}$ (100 samples) via a 1.5 Hz triangle LFO.
- 50% dry + 50% modulated wet summing creates rich pitch-detuned comb-filtering shimmer.

### 6. Tremolo (`RTL/tremolo.sv`)
Implements classic optical/tube amplitude modulation:
- Equation: $y[n] = \frac{x[n] \times \text{gain}[n]}{32768}$.
- Gain is modulated between $(1.0 - \text{DEPTH})$ and $1.0$ by a 4.0 Hz triangle LFO.
- Uses Q15 fixed-point multiplier with zero overflow risk.

### 7. Delay / Echo (`RTL/delay_echo.sv`)
Implements a vintage digital delay line:
- Configurable circular memory buffer up to 500 ms (22,050 samples @ 44.1 kHz).
- Configurable delay time, wet/dry mix, and feedback.
- Saturated addition on the feedback loop prevents clicks or numeric overflow.
- Hardcoded stability clamp on `FEEDBACK_Q15` ($< 28000$) ensures BIBO stability.

### 8. Reverb (`RTL/reverb.sv`)
Algorithmic Schroeder reverberator architecture:
- 4 parallel Feedback Comb Filters (FBCF) with mutually prime delay lengths ($1116, 1188, 1277, 1356$ samples) to prevent metallic flutter ringing.
- 2 cascaded All-Pass Diffusion filters ($225, 556$ samples) to increase echo density.
- Total memory footprint $< 6000$ samples (~11.5 KB), highly synthesizable into single FPGA block RAMs.

### 9. Looper (`RTL/looper.sv`)
Automatic offline phrase looper:
- Configurable loop buffer (e.g. 500 ms / 22,050 samples).
- Automatic offline simulation mode: records the first `LOOP_MS` duration of incoming audio, then seamlessly transitions to looping playback.
- Synthesizable FSM architecture (`STATE_RECORD`, `STATE_PLAY`, `STATE_OVERDUB`, `STATE_STOP`) designed for physical footswitch triggers.

---

## 8. Quick Start Guide

### Step 1: Open MATLAB
Set MATLAB's current folder to `Digital_Pedalboard/MATLAB/`:
```matlab
cd('path/to/Digital_Pedalboard/MATLAB')
```

### Step 2: Verify Toolchain
Run the setup check script in MATLAB:
```matlab
setup_check
```
Expected output:
```
[OK] Icarus Verilog compiler found: Icarus Verilog version 12.0
[OK] VVP simulation runtime found:  Icarus Verilog runtime version 12.0
```

### Step 3: Run the Master Script
Open `run_pedalboard.m` and simply set the **`EFFECT`** parameter in Section 1 to your desired effect number or name:
```matlab
% Set active effect (0 to 8, or -1 for bypass):
EFFECT = 2;  % e.g., 2 or 'distortion'
```

| ID | Name | Description |
|:---:|:---|:---|
| **0** | `'pitch'` | Pitch / Octave (Mode 1: Octave Up, Mode 2: Octave Down) |
| **1** | `'wah'` | Auto-Wah (Chamberlin SVF + LFO formant sweep) |
| **2** | `'distortion'` | Guitar Distortion (Q8 drive + threshold clipping) |
| **3** | `'phaser'` | 4-Stage All-Pass Phaser (Swept notch cancellations) |
| **4** | `'chorus'` | Modulated Delay Chorus (BBD modulation shimmer) |
| **5** | `'tremolo'` | Tremolo (LFO amplitude modulation) |
| **6** | `'delay'` | Echo / Delay (Circular Buffer + Feedback) |
| **7** | `'reverb'` | Schroeder Multi-Comb / All-Pass Reverb |
| **8** | `'looper'` | Phrase Looper (Records then loops playback) |
| **-1** | `'bypass'` | Clean Bypass (All effects disabled, bit-exact dry audio) |

Press **Run** (F5) or run directly from the MATLAB Command Window:
```matlab
run_pedalboard(2)             % Run Distortion by number
run_pedalboard('wah')         % Run Wah by name
run_pedalboard('bypass')      % Run Clean Bypass
run_pedalboard([2, 6])        % Chain Distortion -> Delay
```

The script will automatically:
1. Read `AUDIO.wav`.
2. Convert and write `input_samples.txt`.
3. Auto-generate `SIM/sim_config.svh` with only your selected effect enabled.
4. Compile the SystemVerilog RTL with `iverilog`.
5. Run the simulation using `vvp`.
6. Read `output_samples.txt` and generate `AUDIO/output.wav`.
7. Play the processed audio through your speakers.
8. Display time-domain and frequency-domain verification plots.

---

