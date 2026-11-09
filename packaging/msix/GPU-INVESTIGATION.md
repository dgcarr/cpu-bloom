# Windows GPU metrics investigation

CPU Bloom's OpenGL renderer already works with compatible AMD, Intel and NVIDIA
graphics drivers. The NVIDIA-only limitation is the optional GPU metrics provider,
which currently invokes `nvidia-smi`; it is not a rendering restriction.

On 9 November 2026, a standard-user `Get-Counter` query of
`\GPU Engine(*)\Utilization Percentage` returned live 3D and copy engine readings
on this machine's AMD Radeon 840M (driver 32.0.32015.12012). No additional driver,
elevation or vendor utility was needed for that probe.

Microsoft documents vendor-independent GPU accounting with WDDM 2.0 or newer,
including OpenGL workloads, and uses the busiest engine to represent utilization:
[GPUs in Task Manager](https://devblogs.microsoft.com/directx/gpus-in-the-task-manager/).

An implementation should keep a native PDH query open while visible, aggregate
process instances by adapter and engine, and report the busiest engine for each
adapter. It must distinguish missing counters from zero activity, handle disappearing
instances, and suspend collection while hidden. Use the native API rather than
starting PowerShell for each sample. Multi-adapter selection, localized counters,
integrated/shared memory and packaged standard-user access need testing.

This investigation does not implement that provider. Temperature availability was
not established by the utilization-counter probe; do not display a made-up zero
temperature. Keep temperature optional and separate from utilization support.
