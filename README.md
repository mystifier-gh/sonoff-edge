# eWelink (sonoff) smartthings edge driver

eWelink devices broadcast their status on mDNS locally and can be send commands locally. This edge driver uses mDNS to update device status and local http commands to set its status.
But there information like device key and device type that are required to create the devices. These information never change. Users run a python server locally on computer to seed this information to driver once. The server can stop after that forever.
Everything for then runs on LAN.

Subscribe to [channel](https://bestow-regional.api.smartthings.com/invite/kVM5wOVZvQl5) and install the driver ewelink LAN Driver (0a4bfd5c-adb0-404f-8da4-acc5287372ef)

Then open Smartthings app, ```Add device``` -> ```Search nearby```. You will see a device ```ewelink virtual hub``` Click ```Done```.

You will also see the ewelink devices in 30 seconds. But these devices maynot work as they require encryption key. There are 2 ways to update that.

1. Feed from the server:

Now we need to feed list of devices, their types and keys. We can download this from ewelink cloud. I have a helper program that can exactly do this.

To run server download [hub.zip](https://github.com/bogusfocused/sonoff-edge/blob/main/hub.zip) and run
```
python hub.zip -u <username> -p <password> --region <region> --port <port>
```
you will see something like this with your ip and port:
```
serving at http://10.0.0.41:8003/
press ctrl+C to stop.

```

Open Smartthings app, find the device ```ewelink virtual hub``` , select it and click 3 dots and select ```settings``` . In Url enter the your server URL from above (eg. http://10.0.0.41:8003/ ) and save. You should now see the devices added. 

Stop the server and we do not need it anymore. All stuff from now happens on LAN.

2. Set the device key

To use js script [ewelink.js](https://github.com/bogusfocused/sonoff-edge/blob/main/hub/ewelink.js) run
```
node ewelink.js  "<your username>" "<your password>" "<your region. one of us, cn,eu or as>"
```
From the above json data, extract the device key and set it in the settings.

Go ahead and enjoy !!!


