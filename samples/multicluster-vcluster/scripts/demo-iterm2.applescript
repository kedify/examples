-- Uses iTerm2's documented native scripting interface:
-- https://iterm2.com/documentation-scripting.html
-- Creates only new tabs; runs read-only observers and help, never scaling/reset.
on run arguments
    if (count of arguments) is not 1 then error "Pass the demo directory"
    set demoDirectory to item 1 of arguments
    set commandPrefix to "cd " & quoted form of demoDirectory & " && "
    tell application id "com.googlecode.iterm2"
        if (count of windows) is 0 then
            set demoWindow to (create window with default profile)
            set demoTab to current tab of demoWindow
        else
            set demoWindow to current window
            tell demoWindow
                set demoTab to (create tab with default profile)
            end tell
        end if
        set hostSession to current session of demoTab
        tell hostSession
            set name to "HOST / central control plane"
            set columns to 180
            set rows to 46
            set tenantOne to (split horizontally with default profile)
            set rows to 12
        end tell
        tell tenantOne
            set name to "vc-1 / CPU"
            set rows to 30
            set tenantTwo to (split vertically with default profile)
        end tell
        tell tenantTwo
            set name to "vc-2 / Jobs"
            set tenantThree to (split vertically with default profile)
        end tell
        tell tenantThree
            set name to "vc-3 / new tenant"
        end tell
        -- Session sizing uses the native interface and keeps profile defaults.
        set columns of tenantOne to 60
        set columns of tenantTwo to 60
        set columns of tenantThree to 60
        tell hostSession to write text (commandPrefix & "make demo-pane PANE=host")
        tell tenantOne to write text (commandPrefix & "make demo-pane PANE=1")
        tell tenantTwo to write text (commandPrefix & "make demo-pane PANE=2")
        tell tenantThree to write text (commandPrefix & "make demo-pane PANE=3")
        tell demoWindow
            set controlTab to (create tab with default profile)
        end tell
        tell current session of controlTab
            set name to "Kedify demo / manual controls"
            write text (commandPrefix & "make demo-help")
        end tell
        tell demoTab to select
        tell hostSession to select
        tell demoWindow to select
        activate
        return "Kedify observer tab and manual-control tab are ready"
    end tell
end run
