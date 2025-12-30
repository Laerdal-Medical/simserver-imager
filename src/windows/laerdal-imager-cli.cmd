@echo off

rem
rem For scripting: call laerdal-simserver-imager.exe and wait until it finished before continuing
rem This is necessary because it is compiled as GUI application, and Windows
rem normally does not wait until those exit
rem

start /WAIT laerdal-simserver-imager.exe --cli %*
