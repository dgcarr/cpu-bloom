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

## Initial implementation

`cpu_bloom/WindowsGpuCounters.java` now keeps an English-named native PDH wildcard
query open while visible, reads formatted instance arrays, sums process usage per
physical adapter/engine, and reports the busiest engine across adapters. Invalid
samples are ignored; missing data stays unavailable rather than becoming zero.
The x64 reader bounds allocations and retries instance-list growth up to three times.
The sampler closes the query when hidden and primes a new query on restoration.
No PowerShell subprocess is used. If native query setup fails, the existing NVIDIA
provider is attempted. Temperature and memory are omitted for this initial provider.

Aggregation fixtures and live standard-user sampling/reopening passed on the AMD
840M. The 0.3.4 test package builds and passes package-content checks. Running its
application unpackaged with isolated test preferences also passed native GPU
activity, zero GPU collections/frames while tray-hidden or minimized without tray
handling, and restoration tests. The 0.3.4 MSIX was then installed locally and the
same checks passed inside the actual package context, including live AMD activity,
no hidden GPU collection, and successful restoration (exit code 0).
Intel/NVIDIA, non-English Windows, and multi-adapter machines
still require validation. No claim of universal driver compatibility is made.
