#!/bin/bash

systemctl --user restart --now pipewire.socket

systemctl --user restart --now pipewire-pulse.socket

systemctl --user restart --now wireplumber.service
