
//------------------------------------------------------------------------
//                       Global Variables & Instances
//------------------------------------------------------------------------
import ddf.minim.analysis.*; //for FFT

import brainflow.DataFilter;
import brainflow.FilterTypes;

DataProcessing dataProcessing;
String curTimestamp;
HashMap<Integer,String> index_of_times;

// indexes
final int DELTA = 0; // 1-4 Hz
final int THETA = 1; // 4-8 Hz
final int ALPHA = 2; // 8-13 Hz
final int BETA = 3; // 13-30 Hz
final int GAMMA = 4; // 30-55 Hz

boolean BLINKED = false;
boolean BLINKED_HARD = false;
int blinkCount = 0;

float playback_speed_fac = 1.0f;  //make 1.0 for real-time.  larger for faster playback

//------------------------------------------------------------------------
//                       Global Functions
//------------------------------------------------------------------------


void processNewData() {

    List<double[]> currentData = currentBoard.getData(getCurrentBoardBufferSize());
    int[] exgChannels = currentBoard.getEXGChannels();
    int channelCount = currentBoard.getNumEXGChannels();

    //update the data buffers
    for (int Ichan=0; Ichan < channelCount; Ichan++) {
        for(int i = 0; i < getCurrentBoardBufferSize(); i++) {
            dataProcessingRawBuffer[Ichan][i] = (float)currentData.get(i)[exgChannels[Ichan]];
        }

        dataProcessingFilteredBuffer[Ichan] = dataProcessingRawBuffer[Ichan].clone();
    }

    //apply additional processing for the time-domain montage plot (ie, filtering)
    dataProcessing.process(dataProcessingFilteredBuffer, fftBuff);

    dataProcessing.newDataToSend = true;

    //look to see if the latest data is railed so that we can notify the user on the GUI
    for (int Ichan=0; Ichan < nchan; Ichan++) is_railed[Ichan].update(dataProcessingRawBuffer[Ichan], Ichan);

    //compute the electrode impedance. Do it in a very simple way [rms to amplitude, then uVolt to Volt, then Volt/Amp to Ohm]
    for (int Ichan=0; Ichan < nchan; Ichan++) {
        // Calculate the impedance
        float impedance = (sqrt(2.0)*dataProcessing.data_std_uV[Ichan]*1.0e-6) / BoardCytonConstants.leadOffDrive_amps;
        // Subtract the 2.2kOhm resistor
        impedance -= BoardCytonConstants.series_resistor_ohms;
        // Verify the impedance is not less than 0
        if (impedance < 0) {
            // Incase impedance some how dipped below 2.2kOhm
            impedance = 0;
        }
        // Store to the global variable
        data_elec_imp_ohm[Ichan] = impedance;
    }
}

void initializeFFTObjects(ddf.minim.analysis.FFT[] fftBuff, float[][] dataProcessingRawBuffer, int Nfft, float fs_Hz) {

    float[] fooData;
    for (int Ichan=0; Ichan < nchan; Ichan++) {
        //make the FFT objects...Following "SoundSpectrum" example that came with the Minim library
        fftBuff[Ichan].window(ddf.minim.analysis.FFT.HAMMING);

        //do the FFT on the initial data
        if (isFFTFiltered == true) {
            fooData = dataProcessingFilteredBuffer[Ichan];  //use the filtered data for the FFT
        } else {
            fooData = dataProcessingRawBuffer[Ichan];  //use the raw data for the FFT
        }
        fooData = Arrays.copyOfRange(fooData, fooData.length-Nfft, fooData.length);
        fftBuff[Ichan].forward(fooData); //compute FFT on this channel of data
    }
}

//------------------------------------------------------------------------
//                          CLASSES
//------------------------------------------------------------------------

class DataProcessing {
    private float fs_Hz;  //sample rate
    private int nchan;
    float data_std_uV[];
    float polarity[];
    boolean newDataToSend;
    public BandPassRanges bpRange = BandPassRanges.FiveToFifty;
    public BandStopRanges bsRange = BandStopRanges.Sixty;
    final int[] processing_band_low_Hz = {
        1, 4, 8, 13, 30
    }; //lower bound for each frequency band of interest (2D classifier only)
    final int[] processing_band_high_Hz = {
        4, 8, 13, 30, 55
    };  //upper bound for each frequency band of interest
    float avgPowerInBins[][];
    float headWidePower[];

    // float ch3_mean = 0;
    // float ch4_mean = 0;
    // boolean currentlyBlinking = false;

    DataProcessing(int NCHAN, float sample_rate_Hz) {
        nchan = NCHAN;
        fs_Hz = sample_rate_Hz;
        data_std_uV = new float[nchan];
        polarity = new float[nchan];
        newDataToSend = false;
        avgPowerInBins = new float[nchan][processing_band_low_Hz.length];
        headWidePower = new float[processing_band_low_Hz.length];
    }

    public String getFilterDescription() {
        return bpRange.getDescr();
    }
    public String getShortFilterDescription() {
        return bpRange.getDescr();
    }
    public String getShortNotchDescription() {
        return bsRange.getDescr();
    }

    public synchronized void incrementFilterConfiguration() {
        bpRange = bpRange.next();
    }

    public synchronized  void incrementNotchConfiguration() {
        bsRange = bsRange.next();
    }
    
    private synchronized void processChannel(int Ichan, float[][] data_forDisplay_uV, float[] prevFFTdata) {            
        int Nfft = getNfftSafe();
        double foo;

        //filter the data in the time domain
        // todo use double arrays here and convert to float only to plot data
        try {
            double[] tempArray = floatToDoubleArray(data_forDisplay_uV[Ichan]);
            if (bsRange != BandStopRanges.None) {
                DataFilter.perform_bandstop(tempArray, currentBoard.getSampleRate(), (double)bsRange.getFreq(), (double)4.0, 2, FilterTypes.BUTTERWORTH.get_code(), (double)0.0);
                //println("Bandstop: ");
                //println("Center: " + (double)bsRange.getFreq() + ", Width: " + 4.0);
            }
            if (bpRange != BandPassRanges.None) {
                double centerFreq = (bpRange.getStart() + bpRange.getStop()) / 2.0;
                double bandWidth = bpRange.getStop() - bpRange.getStart();
                //println("Bandpass: ");
                //println("Center: " + centerFreq + ", Width: " + bandWidth + ", Start: " + bpRange.getStart() + ", Stop: " + bpRange.getStop());
                DataFilter.perform_bandpass(tempArray, currentBoard.getSampleRate(), centerFreq, bandWidth, 2, FilterTypes.BUTTERWORTH.get_code(), (double)0.0);
            }
            /*
Bandstop:
Center: 60.0, Width: 4.0
Bandpass:
Center: 27.5, Width: 45.0, Start: 5.0, Stop: 50.0
            */
            doubleToFloatArray(tempArray, data_forDisplay_uV[Ichan]);
        } catch (BrainFlowError e) {
            e.printStackTrace();
        }

        //compute the standard deviation of the filtered signal...this is for the head plot
        float[] fooData_filt = dataProcessingFilteredBuffer[Ichan];  //use the filtered data
        fooData_filt = Arrays.copyOfRange(fooData_filt, fooData_filt.length-((int)fs_Hz), fooData_filt.length);   //just grab the most recent second of data
        data_std_uV[Ichan]=std(fooData_filt); //compute the standard deviation for the whole array "fooData_filt"

        //copy the previous FFT data...enables us to apply some smoothing to the FFT data
        for (int I=0; I < fftBuff[Ichan].specSize(); I++) {
            prevFFTdata[I] = fftBuff[Ichan].getBand(I); //copy the old spectrum values
        }

        //prepare the data for the new FFT
        float[] fooData;
        if (isFFTFiltered == true) {
            fooData = dataProcessingFilteredBuffer[Ichan];  //use the filtered data for the FFT
        } else {
            fooData = dataProcessingRawBuffer[Ichan];  //use the raw data for the FFT
        }
        fooData = Arrays.copyOfRange(fooData, fooData.length-Nfft, fooData.length);   //trim to grab just the most recent block of data
        float meanData = mean(fooData);  //compute the mean
        for (int I=0; I < fooData.length; I++) fooData[I] -= meanData; //remove the mean (for a better looking FFT

        //compute the FFT
        fftBuff[Ichan].forward(fooData); //compute FFT on this channel of data

        // FFT ref: https://www.mathworks.com/help/matlab/ref/fft.html
        // first calculate double-sided FFT amplitude spectrum
        for (int I=0; I <= Nfft/2; I++) {
            fftBuff[Ichan].setBand(I, (float)(fftBuff[Ichan].getBand(I) / Nfft));
        }
        // then convert into single-sided FFT spectrum: DC & Nyquist (i=0 & i=N/2) remain the same, others multiply by two.
        for (int I=1; I < Nfft/2; I++) {
            fftBuff[Ichan].setBand(I, (float)(fftBuff[Ichan].getBand(I) * 2));
        }

        //average the FFT with previous FFT data so that it makes it smoother in time
        double min_val = 0.01d;
        for (int I=0; I < fftBuff[Ichan].specSize(); I++) {   //loop over each fft bin
            if (prevFFTdata[I] < min_val) prevFFTdata[I] = (float)min_val; //make sure we're not too small for the log calls
            foo = fftBuff[Ichan].getBand(I);
            if (foo < min_val) foo = min_val; //make sure this value isn't too small

            if (true) {
                //smooth in dB power space
                foo =   (1.0d-smoothFac[smoothFac_ind]) * java.lang.Math.log(java.lang.Math.pow(foo, 2));
                foo += smoothFac[smoothFac_ind] * java.lang.Math.log(java.lang.Math.pow((double)prevFFTdata[I], 2));
                foo = java.lang.Math.sqrt(java.lang.Math.exp(foo)); //average in dB space
            } else {
                //smooth (average) in linear power space
                foo =   (1.0d-smoothFac[smoothFac_ind]) * java.lang.Math.pow(foo, 2);
                foo+= smoothFac[smoothFac_ind] * java.lang.Math.pow((double)prevFFTdata[I], 2);
                // take sqrt to be back into uV_rtHz
                foo = java.lang.Math.sqrt(foo);
            }
            fftBuff[Ichan].setBand(I, (float)foo); //put the smoothed data back into the fftBuff data holder for use by everyone else
            // fftBuff[Ichan].setBand(I, 1.0f);  // test
        } //end loop over FFT bins

        // calculate single-sided psd by single-sided FFT amplitude spectrum
        // PSD ref: https://www.mathworks.com/help/dsp/ug/estimate-the-power-spectral-density-in-matlab.html
        // when i = 1 ~ (N/2-1), psd = (N / fs) * mag(i)^2 / 4
        // when i = 0 or i = N/2, psd = (N / fs) * mag(i)^2

        for (int i = 0; i < processing_band_low_Hz.length; i++) {
            float sum = 0;
            // int binNum = 0;
            for (int Ibin = 0; Ibin <= Nfft/2; Ibin ++) { // loop over FFT bins
                float FFT_freq_Hz = fftBuff[Ichan].indexToFreq(Ibin);   // center frequency of this bin
                float psdx = 0;
                // if the frequency matches a band
                if (FFT_freq_Hz >= processing_band_low_Hz[i] && FFT_freq_Hz < processing_band_high_Hz[i]) {
                    if (Ibin != 0 && Ibin != Nfft/2) {
                        psdx = fftBuff[Ichan].getBand(Ibin) * fftBuff[Ichan].getBand(Ibin) * Nfft/currentBoard.getSampleRate() / 4;
                    }
                    else {
                        psdx = fftBuff[Ichan].getBand(Ibin) * fftBuff[Ichan].getBand(Ibin) * Nfft/currentBoard.getSampleRate();
                    }
                    sum += psdx;
                    // binNum ++;
                }
            }
            avgPowerInBins[Ichan][i] = sum;   // total power in a band
            // println(i, binNum, sum);
        }
    }

    public void process(float[][] data_forDisplay_uV, ddf.minim.analysis.FFT[] fftData) {              //holds the FFT (frequency spectrum) of the latest data

        float prevFFTdata[] = new float[fftBuff[0].specSize()];

        for (int Ichan=0; Ichan < nchan; Ichan++) { 
            processChannel(Ichan, data_forDisplay_uV, prevFFTdata);
        } //end the loop over channels.

        for (int i = 0; i < processing_band_low_Hz.length; i++) {
            float sum = 0;

            for (int j = 0; j < nchan; j++) {
                sum += avgPowerInBins[j][i];
            }
            headWidePower[i] = sum/nchan;   // averaging power over all channels
        }

        //delta in channel 2 ... avgPowerInBins[1][DELTA];
        //headwide beta ... headWidePower[BETA];

        //find strongest channel
        int refChanInd = findMax(data_std_uV);
        //println("EEG_Processing: strongest chan (one referenced) = " + (refChanInd+1));
        float[] refData_uV = dataProcessingFilteredBuffer[refChanInd];  //use the filtered data
        refData_uV = Arrays.copyOfRange(refData_uV, refData_uV.length-((int)fs_Hz), refData_uV.length);   //just grab the most recent second of data


        //compute polarity of each channel
        for (int Ichan=0; Ichan < nchan; Ichan++) {
            float[] fooData_filt = dataProcessingFilteredBuffer[Ichan];  //use the filtered data
            fooData_filt = Arrays.copyOfRange(fooData_filt, fooData_filt.length-((int)fs_Hz), fooData_filt.length);   //just grab the most recent second of data
            float dotProd = calcDotProduct(fooData_filt, refData_uV);
            if (dotProd >= 0.0f) {
                polarity[Ichan]=1.0;
            } else {
                polarity[Ichan]=-1.0;
            }
        }

        // Check for blinking
        //blink_detect(data_forDisplay_uV);
    }
/*
    public void blink_detect(float[][] data_newest_uV){
        // float ch3_sum = 0;
        // float ch4_sum = 0;

        //if(((abs(data_newest_uV[2][0]) - ch3_mean) > 100) && (abs(data_newest_uV[2][0]) > 100) || ((abs(data_newest_uV[3][0]) - ch4_mean) > 100) && (abs(data_newest_uV[3][0]) > 100)){
        //if(((abs(data_newest_uV[2][0]) - ch3_mean) > 10) && (abs(data_newest_uV[2][0]) > 10)){
        if(data_newest_uV[2][0] > 10 && !currentlyBlinking){
            println(++blinkCount + " Blink");
            BLINKED = true;
            currentlyBlinking = true;
        } else if(data_newest_uV[2][0] < 0 && currentlyBlinking){
            currentlyBlinking = false;
            BLINKED = false;
        } else {
            BLINKED = false;
        }
        //if(data_newest_uV[2][0] > 0){
        //println("Ch.3 newest: " + data_newest_uV[2][0]);}
        // println("Ch.2 newest: " + abs(data_newest_uV[1][0]));
        // println("---");
        // for(int i = 0; i < data_newest_uV.length; i++){
        //     ch3_sum += abs(data_newest_uV[2][i]);
        //     ch4_sum += abs(data_newest_uV[3][i]);
        // }
        // ch3_mean = ch3_sum/4;
        // ch4_mean = ch4_sum/4;
    }*/

    /*
    public void blink_detect_fail(float[][] data_newest_uV){
        float ch1_sum = 0;
        float ch2_sum = 0;

        if(((abs(data_newest_uV[0][0]) - ch1_mean) > 100) && (abs(data_newest_uV[0][0]) > 100) || ((abs(data_newest_uV[1][0]) - ch2_mean) > 100) && (abs(data_newest_uV[1][0]) > 100)){
        //if(((abs(data_newest_uV[0][0]) - ch1_mean) > 100) && (abs(data_newest_uV[0][0]) > 100)){
            println(++blinkCount + " Blink");
            BLINKED = true;
        } else {
            BLINKED = false;
        }
        // println("Ch.1 newest: " + abs(data_newest_uV[0][0]));
        // println("Ch.2 newest: " + abs(data_newest_uV[1][0]));
        // println("---");
        for(int i = 0; i < data_newest_uV.length; i++){
            ch1_sum += abs(data_newest_uV[0][i]);
            ch2_sum += abs(data_newest_uV[1][i]);
        }
        ch1_mean = ch1_sum/4;
        ch2_mean = ch2_sum/4;
    }*/
}