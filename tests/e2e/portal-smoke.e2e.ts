import { test } from '@e2e-dev/web';
import { expect } from 'e2e';

test('the configured captive portal endpoint renders a page', async ({ app, browser }) => {
  await app.open(process.env.OPEN_HOTSPOT_E2E_PATH ?? '/');
  await expect(browser.locator('body')).toBeVisible();
});
