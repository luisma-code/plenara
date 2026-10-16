// The icon extends the approved app palette and six-part botanical motif.
const sharp = require('sharp');
const fs = require('node:fs');
const folder = 'ios/Plenara/Assets.xcassets/AppIcon.appiconset';
const artwork = (dark=false) => fs.readFileSync(`design/icon/plenara${dark ? '-dark' : ''}.svg`);
(async () => {
  for (const [dark, name] of [[false,'Icon'],[true,'Icon-dark']]) {
    await sharp(artwork(dark)).flatten().removeAlpha().png().toFile(`${folder}/${name}.png`);
  }
  const w=1500,h=1060;
  let layers=[];
  let base=`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><rect width="100%" height="100%" fill="#F8F6F2"/><text x="70" y="100" font-size="52" font-family="Georgia,serif" fill="#302C39">A little closer.</text><text x="70" y="145" font-size="22" font-family="Helvetica,sans-serif" fill="#716B78">Plenara · a softer bloom, in the app’s own colors</text><text x="70" y="865" font-size="20" font-family="Helvetica,sans-serif" fill="#716B78">LIGHT</text><text x="710" y="865" font-size="20" font-family="Helvetica,sans-serif" fill="#716B78">DARK</text><text x="70" y="1005" font-size="18" font-family="Helvetica,sans-serif" fill="#716B78">iPhone-size previews</text></svg>`;
  for (const [i,name] of ['Icon','Icon-dark'].entries()) {
    let mask=Buffer.from('<svg width="560" height="560"><rect width="560" height="560" rx="125" fill="white"/></svg>');
    let rounded=await sharp(`${folder}/${name}.png`).resize(560).composite([{input:mask,blend:'dest-in'}]).png().toBuffer();
    layers.push({input:rounded,left:70+i*640,top:230});
    for(const [j,size]of [60,40,29].entries()) {
      let small=await sharp(`${folder}/${name}.png`).resize(size).png().toBuffer();
      let smask=Buffer.from(`<svg width="${size}" height="${size}"><rect width="${size}" height="${size}" rx="${size*.225}" fill="white"/></svg>`);
      small=await sharp(small).composite([{input:smask,blend:'dest-in'}]).png().toBuffer();
      layers.push({input:small,left:70+i*640+j*100,top:900});
    }
  }
  await sharp(Buffer.from(base)).composite(layers).png().toFile('verification/icon-preview.png');
  console.log('Rendered light/dark app icons and size review.');
})().catch(e=>{console.error(e);process.exitCode=1});
