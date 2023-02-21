# rut-fw

Firmware update script for integration with [Teltonika RMS](https://rms.teltonika-networks.com/).

Haven't written a detailed readme yet.

Basically, you have to 

- clone this repo or host this somewhere on your own webserver.
- Edit model_map.cfg to support your models (out of the box I only put in RUT240 and RUTX11)
- create/edit the individual RUTxxx.cfg files to specify desired firmware
- copy fwup.sh to your device and execute it with -i flag, passing optional HH MM params to pick time of day (or it will use defaults from the script, which is 4:45am)
- Use RMS task scheduler (to operate on multiple devices simultaneously) or directly via SSH on the device to schedule the upgrade.
- From then on, device will keep auto-updating as you make changes to the cfg files, nothing left to do.
- Run again with -u param to uninstall/disable
