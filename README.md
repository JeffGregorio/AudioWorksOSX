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
* Scope can be full-screened using (cmd + f)

