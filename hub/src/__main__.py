from socket import AF_INET6
from ewelink import XRegistryCloud
import aiohttp
import asyncio
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from netifaces import interfaces, ifaddresses, AF_INET


class JsonHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, fetch_data=None, **kwargs):
        self.fetch_data = fetch_data
        super().__init__(*args, **kwargs)

    def do_GET(self):
        data = self.fetch_data().encode()
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.send_header("Content-Length", len(data))
        self.end_headers()
        self.wfile.write(data)


def ip4_addresses():
    ip_list = []
    for interface in interfaces():
        for link in ifaddresses(interface)[AF_INET]:
            if link["addr"].startswith("192.168.") or link["addr"].startswith("10."):
                ip_list.append(link["addr"])
    return ip_list


REGION = "us"


async def get_devices(username, password, region=REGION):
    async with aiohttp.ClientSession() as session:
        registry = XRegistryCloud(session)
        registry.region = region
        await registry.login(username=username, password=password, app=1)
        devices = await registry.get_devices()
        print(devices)
        devices = [
            {
                k: d[k]
                for k in [
                    "name",
                    "deviceid",
                    "devicekey",
                    "brandName",
                    "brandLogo",
                    "showBrand",
                    "productModel",
                    "online",
                    "params",
                    "extra",
                ]
            }
            for d in devices
        ]
        return json.dumps(devices)


PORT = 8008


def main(username, password, region=REGION, address="", port=PORT, **kwargs):
    def fetch_data():
        return asyncio.run(get_devices(username, password, region=region))

    class Handler(JsonHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, fetch_data=fetch_data, **kwargs)

    try:
        with HTTPServer((address, port), RequestHandlerClass=Handler) as httpd:
            if address == "":
                address = ip4_addresses()[0]
            print(f"serving at http://{address}:{httpd.server_port}/")
            print("press ctrl+C to stop.")
            httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.shutdown()


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("-u", "--username", required=True, help="your ewelink username")
    parser.add_argument("-p", "--password", required=True, help="your ewelink password")
    parser.add_argument(
        "-r",
        "--region",
        default="us",
        choices=["us", "cn", "eu", "as"],
        help="your ewelink server region",
    )
    parser.add_argument(
        "-b",
        "--bind",
        metavar="ADDRESS",
        help="bind to this address " "(default: all interfaces)",
    )

    parser.add_argument(
        "--port",
        default=PORT,
        type=int,
        help="bind to this port " "(default: %(default)s)",
    )
    args = parser.parse_args()

    main(**vars(args))
