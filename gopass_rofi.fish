# ~/.config/fish/functions/gopass_rofi.fish
#
# Usage:
#   gopass_rofi          → copy password to clipboard
#   gopass_rofi --show   → show password in rofi (visible)
#   gopass_rofi --otp    → copy OTP/TOTP code
#   gopass_rofi --user   → copy username field
#   gopass_rofi --type   → type password via xdotool (X11 only, skip on Wayland)

function gopass_rofi --description "Search and copy passwords from gopass using rofi"

    # ── parse flags ──────────────────────────────────────────────────────────
    set -l mode "password"   # password | otp | user | show
    set -l do_type 0

    for arg in $argv
        switch $arg
            case --show
                set mode "show"
            case --otp
                set mode "otp"
            case --user
                set mode "user"
            case --type
                set do_type 1
            case --help -h
                echo "Usage: gopass_rofi [--show] [--otp] [--user] [--type]"
                echo ""
                echo "  (no flag)   Copy password to clipboard (cleared after 45s)"
                echo "  --show      Display password in a rofi prompt (visible)"
                echo "  --otp       Copy OTP/TOTP code"
                echo "  --user      Copy the 'user' / 'login' metadata field"
                echo "  --type      Type the password via wtype (Wayland)"
                return 0
        end
    end

    # ── pick an entry via rofi ───────────────────────────────────────────────
    set -l entry (
        gopass ls --flat 2>/dev/null \
        | rofi \
            -dmenu \
            -i \
            -p "gopass" \
            -theme-str 'window {width: 40%;} listview {lines: 12;}' \
            -mesg "Select a password entry"
    )

    # user cancelled
    if test -z "$entry"
        return 1
    end

    # ── act on the chosen entry ──────────────────────────────────────────────
    switch $mode

        case "password"
            # copy silently; gopass clears clipboard after timeout (default 45s)
            if gopass show --password "$entry" 2>/dev/null | wl-copy --trim-newline
                _gopass_notify "🔑 Copied" "$entry" "Password in clipboard (45s)"
                # schedule clipboard wipe after 45 s
                fish -c "sleep 45; wl-copy --clear" &
            else
                _gopass_notify "❌ Error" "$entry" "Could not retrieve password"
                return 1
            end

        case "show"
            set -l secret (gopass show --password "$entry" 2>/dev/null)
            if test -z "$secret"
                _gopass_notify "❌ Error" "$entry" "Could not retrieve password"
                return 1
            end
            # show inside rofi — user can manually copy from the prompt
            echo "$secret" \
            | rofi \
                -dmenu \
                -p "password" \
                -mesg "$entry" \
                -theme-str 'window {width: 35%;} entry {placeholder: "";}' \
                > /dev/null

        case "otp"
            set -l code (gopass otp --clip=false "$entry" 2>/dev/null | string match -r '\d{6,8}')
            if test -z "$code"
                _gopass_notify "❌ Error" "$entry" "No OTP found (check totp: field)"
                return 1
            end
            echo -n "$code" | wl-copy
            _gopass_notify "⏱  OTP Copied" "$entry" "Code: $code (clipboard clears in 30s)"
            fish -c "sleep 30; wl-copy --clear" &

        case "user"
            # try common field names
            set -l username ""
            for field in user username login email
                set username (gopass show "$entry" 2>/dev/null | grep -i "^$field:" | head -1 | string replace -r '^[^:]+:\s*' '')
                if test -n "$username"
                    break
                end
            end
            if test -z "$username"
                _gopass_notify "❌ Not found" "$entry" "No user/login field in this entry"
                return 1
            end
            echo -n "$username" | wl-copy
            _gopass_notify "👤 Username copied" "$entry" "$username"

    end

    # ── optional: type via wtype (Wayland) ───────────────────────────────────
    if test $do_type -eq 1
        set -l secret (wl-paste 2>/dev/null)
        if test -n "$secret"
            wtype "$secret"
        end
    end
end


# ── helper: send a desktop notification (graceful fallback) ─────────────────
function _gopass_notify --description "Send desktop notification or echo"
    set -l summary $argv[1]
    set -l title   $argv[2]
    set -l body    $argv[3]

    if command -q notify-send
        notify-send --urgency=low --expire-time=3000 "$summary – $title" "$body"
    else
        echo "[$summary] $title — $body"
    end
end


# ── convenient short aliases ─────────────────────────────────────────────────
abbr --add gp   'gopass_rofi'
abbr --add gpo  'gopass_rofi --otp'
abbr --add gpu  'gopass_rofi --user'
abbr --add gps  'gopass_rofi --show'
