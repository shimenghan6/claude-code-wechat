"""System volume control via pycaw."""
import sys
from pycaw.pycaw import AudioUtilities

vol = AudioUtilities.GetSpeakers().EndpointVolume

if len(sys.argv) < 2:
    cur = vol.GetMasterVolumeLevelScalar()
    muted = vol.GetMute()
    print(f"{'MUTED' if muted else 'ON'} at {int(cur * 100)}%")
elif sys.argv[1] == "mute":
    vol.SetMute(True, None)
    print("Muted")
elif sys.argv[1] == "unmute":
    vol.SetMute(False, None)
    print("Unmuted")
else:
    try:
        pct = int(sys.argv[1])
        vol.SetMasterVolumeLevelScalar(pct / 100.0, None)
        vol.SetMute(pct == 0, None)
        print(f"Volume set to {pct}%")
    except ValueError:
        print("Usage: volume.py [mute|unmute|<0-100>]")
