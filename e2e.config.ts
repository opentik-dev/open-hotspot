import type { E2EConfig } from 'e2e';
import { web } from '@e2e-dev/web';

/**
 * This suite is intentionally external to the OpenWrt package test suite.
 * A real router is contacted only when OPEN_HOTSPOT_E2E_URL is supplied.
 */
export default {
  targets: [{
    engine: web(),
    app: {
      // A closed local default prevents accidental traffic to the router.
      url: process.env.OPEN_HOTSPOT_E2E_URL ?? 'http://127.0.0.1:9',
    },
  }],
} satisfies E2EConfig;
