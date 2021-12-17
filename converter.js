var fs = require('fs');
var path = require('path');
var glob = require("glob");

function bufferFile(relPath) {
    return fs.readFileSync(path.join(__dirname, relPath), { encoding: 'utf8' }); // zzzz....
}

glob("../../../WTF/**/Experience.lua", function (er, files) {
    files.forEach(file => {
        var lua = bufferFile(file);
        var json = 
            lua
            .replace("ExperienceDB = ", "")
            .replace(/\[\"(.+)\"\] =/g, (substring, m1) => '"' + m1 + '":')
            .replace(/-- \[.+\]/g, () => "")
            .replace(/\,\s*\n\s*[\}\]]/g, (substring) => substring.replace(",", ""));

        json = JSON.parse(json);

        Object.keys(json.profileKeys).forEach((profile) => {
            var xps = json.char[profile].xp_gains;
            for (const [key, value] of Object.entries(xps)) {
                console.log(value);
            };
        });
    });
})

 
