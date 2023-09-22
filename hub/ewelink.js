
const crypto = require('node:crypto');
const http = require('node:http');
const { networkInterfaces } = require('os');



const APP = [
    ["4s1FXKC9FaGfoqXhmXSJneb3qcm1gOak", "oKvCM06gvwkRbfetd6qWRrbC3rFrbIpV"],
    ["R8Oq3y0eSZSYdKccHlrQzT1ACCOUT9Gv", "1ve5Qk9GXfUhKAn1svnKwpAlxXkMarru"],
]
const API = {
    "cn": "https://cn-apia.coolkit.cn",
    "as": "https://as-apia.coolkit.cc",
    "us": "https://us-apia.coolkit.cc",
    "eu": "https://eu-apia.coolkit.cc",
}
async function encode(key, payload) {
    const encoder = new TextEncoder()
    const keyBytes = encoder.encode(key);
    const messageBytes = encoder.encode(JSON.stringify(payload));

    const cryptoKey = await crypto.subtle.importKey(
        'raw', keyBytes, { name: 'HMAC', hash: 'SHA-256' },
        true, ['sign']
    );
    const sig = await crypto.subtle.sign('HMAC', cryptoKey, messageBytes);

    // to base64
    return btoa(String.fromCharCode(...new Uint8Array(sig)));
}
async function login(username, password, region) {
    console.assert(username.length > 0, "username must be present")
    console.assert(password.length > 0, "password must be present")
    console.assert(Object.keys(API).includes(region), "region must be one of %s but was %s", Object.keys(API).join(), region)
    let app = 1;
    let payload = {
        "password": password,
        "countryCode": "+86",
    }
    if (username.includes("@")) { payload["email"] = username }
    else if (username.indexOf("+") == 0) { payload["phoneNumber"] = username }
    else
        payload["phoneNumber"] = "+" + username
    let hex_dig = await encode(APP[app][1], payload)

    let headers = {
        "Authorization": "Sign " + hex_dig,
        "Content-Type": "application/json",
        "X-CK-Appid": APP[app][0],
    }

    let response = await fetch(
        API[region] + "/v2/user/login", {
        method: "POST",
        headers: headers,
        body: JSON.stringify(payload)
    }
    )
    let json = await response.json();
    if (json.error != 0) {
        console.log(JSON.stringify(json, null, 4));
        return;
    }
    let at = json.data.at
    response = await fetch(
        API[region] + "/v2/device/thing", {
        method: "GET",
        headers: { "Authorization": "Bearer " + at }
    }
    )
    json = await response.json();
    if (json.error != 0) {
        console.log(JSON.stringify(json, null, 4));
        return;
    }
    const result = {}
    for (const d of json["data"]["thingList"])
        result[d["itemData"]["deviceid"]] = d["itemData"]
    return result
}

function getIPAddress() {
    const nets = networkInterfaces();
    for (const net of Object.values(nets)) {
        for (const addr of net) {
            // Skip over non-IPv4 and internal (i.e. 127.0.0.1) addresses
            // 'IPv4' is in Node <= 17, from 18 it's a number 4 or 6
            const familyV4Value = typeof addr.family === 'string' ? 'IPv4' : 4
            if (addr.family === familyV4Value && !addr.internal) {
                return addr.address;
            }
        }
    }
}
async function serve(arguments) {
    console.assert(arguments.length >= 5, "wrong number of arguments.")
    const username = arguments[2];
    const password = arguments[3];
    const region = arguments[4];
    const port = arguments.length > 5 ? arguments[5] : 8003
    const json = await login(username, password, region)
    if (json == null) return
    const response = JSON.stringify(json);
    console.log(JSON.stringify(json, null, 4));
    const server = http.createServer();
    server.on("request", (req, res) => {
        console.log("sending data")
        res.setHeader('Content-type', 'application/json')
        res.setHeader('Connection', 'close')
        res.setHeader('Content-Length', Buffer.byteLength(response, "utf8"))
        res.setHeader('Server', 'BaseHTTP/0.6 Python/3.11.5')
        res.write(response, "utf8")
        res.end();
    })
    server.on("connection", (socket) => {
        console.log(`Recv request from ${socket.remoteAddress}`)
    })
    server.on("error", (err) => {
        console.log(err)
    })
    server.on('clientError', (err, socket) => {
        console.log(err)
        socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
    });
    console.log(`\n\n\n\nserving at http://${getIPAddress()}:${port}/`)
    server.listen(port, "0.0.0.0");
}

serve(process.argv)

