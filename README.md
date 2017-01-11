# AudioWorksOSX

Audio visualizer app used for LiveConnections Bridge Session: Cybersounds in 2016 and 2017. 

## Dependencies ##
* portaudio (place headers in /opt/local/include, and dylib in /opt/local/include)

## Usage notes ##
* Requires multichannel audio interface (used 8-channel Tascam US-1800)
  * Select interface under preferences menu (cmd + ,)
* Scope has multiple modes
  * Time domain (multiple waveforms stacked vertically)
  * Frequency domain (multiple spectra overlaid in different colors)
  * Time-frequency (experimental, incomplete)
  * Time domain mode was the only mode ultimately used in the performance
* Scope mode and other options can be set under Window->Time-Frequency Scope Parameters in the menu bar
  * Note: the window name is a bit of a misnomer, since it was quickly repurposed to add needed general controls to the scope after the time-frequency view was abandoned.
  * Use the first slider to adjust global input gain
  * Use the second slider to set the scope horizontal axis limits
   * The "Short/Long" segmented control was an attempt to automate zooming in and out to the two time scales used in the performance, but is buggy. Do it manually using the slider. 
* Scope can be full-screened using (cmd + f)
