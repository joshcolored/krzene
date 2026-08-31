import sharp from "sharp";

const source = "public/krzene-mark.svg";

await Promise.all([
  sharp(source).resize(192, 192).png().toFile("public/icon-192.png"),
  sharp(source).resize(512, 512).png().toFile("public/icon-512.png"),
  sharp(source)
    .resize(384, 384)
    .extend({ top: 64, bottom: 64, left: 64, right: 64, background: "#070707" })
    .png()
    .toFile("public/icon-512-maskable.png"),
  sharp(source).resize(180, 180).png().toFile("public/apple-touch-icon.png"),
]);

console.log("Generated Krzene PWA icons.");
