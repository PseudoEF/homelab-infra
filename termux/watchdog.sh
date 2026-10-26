#!/data/data/com.termux/files/usr/bin/sh
# Keeps runit alive on Android. The phantom-process killer can reap
# runsvdir while service processes survive as orphans; recover in that case.
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export HOME=/data/data/com.termux/files/home
export SVDIR=$PREFIX/var/service
LOG="$HOME/logs/watchdog.log"
mkdir -p "$HOME/logs"

if pgrep -x runsvdir >/dev/null 2>&1; then
  # Android may freeze a single service when the screen is off.
  for s in sshd nginx panel gordaya cloudflared panel-demo gordaya-demo; do
    case "$(sv status "$s" 2>&1)" in
      *paused*) sv cont "$s" >/dev/null 2>&1 ;;
    esac
  done
  exit 0
fi

echo "$(date -Iseconds) runsvdir missing, recovering" >> "$LOG"

# Orphans must be gone before runit can bind their ports.
pkill -f "[s]shd -D" 2>/dev/null || true
pkill -f "[n]ext-server" 2>/dev/null || true
pkill -f "[p]anel/server.js" 2>/dev/null || true
pkill -f "[p]anel-demo/server.js" 2>/dev/null || true
pkill -f "[n]ginx: master" 2>/dev/null || true
pkill -f "[n]ginx: worker" 2>/dev/null || true
pkill -f "[c]loudflared" 2>/dev/null || true
pkill -f "[p]ostgres -D" 2>/dev/null || true
pkill -f "[r]edis-server" 2>/dev/null || true
pkill -f "[s]sh-agent" 2>/dev/null || true

for i in 1 2 3 4 5 6 7 8 9 10; do
  busy=0
  for p in 3000 3001 8080 8081 8082; do
    (exec 3<>/dev/tcp/127.0.0.1/$p) 2>/dev/null && { busy=1; exec 3>&-; }
  done
  [ "$busy" -eq 0 ] && break
  sleep 1
done

setsid nohup runsvdir "$SVDIR" >> "$HOME/logs/runsvdir.log" 2>&1 < /dev/null &
sleep 6

for s in sshd nginx panel gordaya cloudflared panel-demo gordaya-demo; do
  rm -f "$SVDIR/$s/down"
  sv up "$s" >/dev/null 2>&1 || true
done
sleep 4
sv status sshd nginx panel gordaya cloudflared panel-demo gordaya-demo >> "$LOG" 2>&1
