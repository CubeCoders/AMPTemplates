import puppeteer from 'puppeteer-extra';
import StealthPlugin from 'puppeteer-extra-plugin-stealth';
import fs from 'fs/promises';

puppeteer.use(StealthPlugin());

const pageUrl = 'https://www.minecraft.net/en-us/download/server/bedrock';

const browser = await puppeteer.launch({
  headless: 'new',
  args: [
    '--no-sandbox',
    '--disable-setuid-sandbox',
    '--disable-http2',
    '--disable-dev-shm-usage',
    '--disable-gpu',
    '--disable-features=IsolateOrigins,site-per-process'
  ]
});

try {
  const page = await browser.newPage();

  await page.setUserAgent(
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36'
  );

  await page.goto(pageUrl, { waitUntil: 'networkidle2', timeout: 120000 });

  // Wait for release .zip links to be visible
  await page.waitForSelector('a[href$=".zip"]', { timeout: 30000 });

  // Grab release URLs
  const releaseLinks = await page.evaluate(() => {
    const anchors = Array.from(document.querySelectorAll('a[href$=".zip"]'));
    return {
      Linux: anchors.find(a => a.href.includes('bin-linux/') && !a.href.includes('preview'))?.href || null,
      Windows: anchors.find(a => a.href.includes('bin-win/') && !a.href.includes('preview'))?.href || null
    };
  });

  // Click preview radio buttons to load preview download links
  const previewLinks = {};

  for (const [labelOptions, key, match] of [
    [['Ubuntu (Linux) Preview'], 'Linux', 'bin-linux-preview/'],
    [['Window Preview', 'Windows Preview'], 'Windows', 'bin-win-preview/']
  ]) {
    // Wait for any matching label text
    await page.waitForFunction(
      (texts) => [...document.querySelectorAll('label')].some(l => texts.includes(l.textContent.trim())),
      {},
      labelOptions
    );

    // Click the corresponding label
    await page.evaluate((texts) => {
      const label = [...document.querySelectorAll('label')].find(l => texts.includes(l.textContent.trim()));
      if (label) label.click();
    }, labelOptions);

    // Wait for preview .zip link to appear
    await page.waitForFunction(
      (match) => [...document.querySelectorAll('a[href$=".zip"]')].some(a => a.href.includes(match)),
      { timeout: 15000 },
      match
    );

    // Grab the preview URL
    previewLinks[key] = await page.evaluate((match) => {
      const a = [...document.querySelectorAll('a[href$=".zip"]')].find(a => a.href.includes(match));
      return a ? a.href : null;
    }, match);
  }

  const allLinks = {
    Release: releaseLinks,
    Preview: previewLinks
  };

  // Sanity check
  const missing = [];
  if (!allLinks.Release.Linux) missing.push('Release Linux');
  if (!allLinks.Release.Windows) missing.push('Release Windows');
  if (!allLinks.Preview.Linux) missing.push('Preview Linux');
  if (!allLinks.Preview.Windows) missing.push('Preview Windows');
  if (missing.length > 0) {
    throw new Error(`❌ One or more download URLs are missing: ${missing.join(', ')}`);
  }

  // Write to file
  await fs.writeFile('bedrock-urls.json', JSON.stringify(allLinks, null, 2));
  console.log('✅ Bedrock download URLs scraped successfully.');

} catch (err) {
  console.error('❌ Failed to scrape Bedrock URLs:', err.message);
  process.exit(1);
} finally {
  await browser.close();
}
