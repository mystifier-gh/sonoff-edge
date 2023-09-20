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
    console.log(json);
    if (json.error != 0) return;
    let at = json.data.at
    response = await fetch(
        API[region] + "/v2/device/thing", {
        method: "GET",
        headers: { "Authorization": "Bearer " + at }
    }
    )
    json = await response.json();
    console.log(JSON.stringify(json));
}

var arguments = process.argv;
console.assert(arguments.length == 5, "wrong number of arguments.")
login(arguments[2], arguments[3], arguments[4]).then(x => x)