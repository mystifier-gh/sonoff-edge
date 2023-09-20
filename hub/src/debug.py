import aiohttp
import asyncio
from ewelink import XRegistryCloud, XRegistryLocal
import yaml

from ewelink import XDevice


async def get_devices(username, password, region):
    async with aiohttp.ClientSession() as session:
        registry = XRegistryCloud(session)
        registry.region = region
        await registry.login(username=username, password=password, app=1)
        device_infos = await registry.get_devices()
        devices = [XDevice(d) for d in device_infos]
        dev= devices[1]
        dev["host"]="10.1.1.225"
        local = XRegistryLocal(session)
        await local.send(device=dev, command="switch", params={"switch": "on"})


with open(".secrets/creds.yml", "r") as f:
    creds = yaml.safe_load(f)

asyncio.run(get_devices(creds["username"], creds["password"], region=creds["region"]))
