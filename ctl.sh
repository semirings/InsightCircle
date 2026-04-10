#!/usr/bin/env bash

sudo mv ~/populi.Wk/InsightCircle/insight_calc/insight-calc.service /etc/systemd/system/
sudo mv ~/populi.Wk/InsightCircle/insight_store/insight-store.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl restart insight-calc
sudo systemctl restart insight-store