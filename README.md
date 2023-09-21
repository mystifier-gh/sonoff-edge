# eWelink (sonoff and other brands) smartthings edge driver

eWelink devices broadcast their status on mDNS (which works on LAN) and can be send commands on LAN. This edge driver uses mDNS to update device state and http commands over LAN to set device states.

eWelink encrypts the communication, both mDNS broadcasts and http commands for non-DIY mode devices. The decryption key is ```devicekey``` and can be retrived from eWelink server using eWelink credentials. Each device type is identified using ```uiid``` and can be used to configure the devices in greater detail. ```uiid``` can also be retrived along with ```devicekey``` and lots of other device data from eWelink server.  ```devicekey``` and ```uiid``` possibily never change during the lifetime of device. 

## Steps to install

### Install the driver and search for the virtual hub

Subscribe to [channel](https://bestow-regional.api.smartthings.com/invite/kVM5wOVZvQl5) and install the driver ewelink LAN Driver (0a4bfd5c-adb0-404f-8da4-acc5287372ef)

Then open Smartthings app, ```Add device``` -> ```Search nearby```. You will see a device ```ewelink virtual hub``` Click ```Done```.

You will also see the ewelink devices in 30 seconds. But these devices maynot work as they require encryption key.

### Update the devices with eWelink data

There are 2 ways to update that.

* Feed from the server:

    Users run a python server locally on computer to seed this information to driver once. The server can stop after that forever.
Now we need to feed list of devices, their types and keys. We can download this from ewelink cloud. I have a helper program that can exactly do this.

    To run server download [hub.zip](https://github.com/bogusfocused/sonoff-edge/blob/main/hub.zip) and run
   
   ```console
    python hub.zip -u username -p password --region region --port port
    ```

    you will see something like this with your ip and port:
    
    ```console
    serving at http://10.0.0.41:8003/
    press ctrl+C to stop.
    
    ```

    Open Smartthings app, find the device ```ewelink virtual hub``` , select it and click 3 dots and select ```settings``` . In Url enter the your server URL from above (eg. http://10.0.0.41:8003/ ) and save. You should now see the devices added. 

    Stop the server and we do not need it anymore. All stuff from now happens on LAN.

* Set the device key

    To use js script [ewelink.js](https://github.com/bogusfocused/sonoff-edge/blob/main/hub/ewelink.js)

    Ensure node version is v20 or newer. We use crypto library which is found in v20 versions.
    ```console
    node -v 
    v20.6.1
    ```
    then run the script
    ```console
    node ewelink.js  "your username" "your password" "your region. one of us, cn,eu or as"
    ```
    From the above json data, extract the device key and set it in the settings.


## To add support for a device

The types of device supported by ewelink is identified by uiid. In the above json dump you will see the value for each of the devices at ```data.thingList.itemData.extra.uiid```

For example:
```json
{
    "error": 0,
    "msg": "",
    "data": {
        "thingList": [
            {
                "itemType": 1,
                "itemData": {
                    "name": "Hallway light",
                    "deviceid": "xxxxxxxxx",
                    "extra": {
                        "uiid": 1,
                        "description": "xxxxxxxx",
                        "brandId": "5c4c1aee3a7d24c7100be054",
```
Each uiid is explained in [UIIDProtocol](https://coolkit-technologies.github.io/eWeLink-API/#/en/UIIDProtocol) 

Add a smartthings device profile for the uiid and corresponding handlers.


