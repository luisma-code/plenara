#!/usr/bin/env python3
"""Compatibility command for the current compact Home evidence exporter.
Earlier ranking captures remain historical under verification/ranking.
"""
import runpy
runpy.run_path('tool/export-compact-home-verification.py', run_name='__main__')
