import { useRouter } from 'expo-router';
import { useEffect } from 'react';

/**
 * The relay's visible half -- which is to say, none of it.
 *
 * A widget row links to `simplephonern://open?u=<target>`, because iOS always
 * delivers a widget tap to the widget's own host app. Two things then happen
 * independently from the one delivery: the root layout opens the target (see
 * `relayDeepLink` there, which parses the RAW url because Expo Router's own
 * path extraction mangles the payload), and Expo Router navigates here. This
 * screen's entire job is to undo that navigation.
 *
 * It deliberately does NOT open anything. Both halves come from the same iOS
 * delivery, so if this screen mounted, the layout already fired; opening again
 * here would race the first open with the app mid-backgrounding.
 */
export default function RelayScreen() {
  const router = useRouter();

  useEffect(() => {
    // `back()`, never `replace('/')` while there is somewhere to go back to.
    // A relay can arrive while the Appearance or the form sheet is open, and
    // popping only this screen leaves that sheet standing -- which is what
    // URLRelay did, since it dismissed nothing and did not care what was on
    // top. `presentation: 'transparentModal'` plus `animation: 'none'` in the
    // root layout is what makes the round trip invisible.
    //
    // `replace('/')` is the cold-launch floor: if the anchor ever fails to seed
    // `index` beneath us, this screen is the whole stack and there is no back.
    if (router.canGoBack()) {
      router.back();
    } else {
      router.replace('/');
    }
  }, [router]);

  return null;
}
