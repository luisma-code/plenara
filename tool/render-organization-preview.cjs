const sharp = require('sharp');
const width = 1800, height = 1530;
const svg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}"><rect width="100%" height="100%" fill="#E9E5E6"/><text x="54" y="77" font-family="Georgia,serif" font-size="52" fill="#302C39">Your people, organized in a few taps.</text><text x="54" y="128" font-family="Helvetica,sans-serif" font-size="24" fill="#716B78">Select a group. Apply shared details. Or sort one attribute at a time.</text><text x="54" y="1497" font-family="Helvetica,sans-serif" font-size="20" fill="#716B78">PLENARA / NATIVE IPHONE CAPTURES / FICTIONAL PEOPLE</text></svg>`);
(async () => {
  const layers = [];
  for (const [i, name] of ['selected', 'shared', 'quick-sort'].entries()) {
    const input = await sharp(`verification/organize/${name}.png`).resize(540, 1174).png().toBuffer();
    layers.push({ input, left: 54 + i * 576, top: 200 });
  }
  await sharp(svg).composite(layers).png().toFile('verification/organize/preview.png');
  console.log('Rendered organize/preview.png from current native captures.');
})().catch(error => { console.error(error); process.exitCode = 1; });
