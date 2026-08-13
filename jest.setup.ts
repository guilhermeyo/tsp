import { jest } from '@jest/globals';

/**
 * The native module is a JSI binding into the app target, so it does not exist
 * in a Node process. It is mocked once here rather than per suite because every
 * function on it is a pure lookup and the modules under test only care that
 * they get a value of the right shape back.
 *
 * These are also the three places where a test could accidentally depend on the
 * MACHINE running it, since `preferredLanguage` and `prefersMetric` read the
 * host's locale and region. Pinning them here is what makes the suite give the
 * same answer on any laptop and in CI.
 *
 * Mocked at the module path the source imports, not at a `@/` alias: this file
 * lives outside `src`, and the alias would resolve to a different module id.
 */
jest.mock('./modules/launcher-native', () => ({
  LauncherNative: {
    appGroupId: 'group.com.guilherme44.simple-phone',
    configKey: 'launcher_config',
    readConfigJSON: jest.fn((): string | null => null),
    writeConfigJSON: jest.fn(),
    reloadWidget: jest.fn(),
    resolvedFontFamily: jest.fn((): string | null => null),
    preferredLanguage: jest.fn((): string => 'en-US'),
    prefersMetric: jest.fn((): boolean => true),
    readQuoteStatsJSON: jest.fn((): string | null => null),
  },
}));

/**
 * `randomUUID` is a native call too, and it is the one place a test could not
 * be deterministic. Counted rather than random so a failure names the row that
 * got the id, and reset between tests by `jest.clearAllMocks`.
 */
jest.mock('expo-crypto', () => {
  let n = 0;
  return { randomUUID: jest.fn((): string => `00000000-0000-4000-8000-${String(++n).padStart(12, '0')}`) };
});
