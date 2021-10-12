function bwbench(;
    N::Integer=120_000_000,
    niter::Integer=10,
    verbose::Bool=false,
    nthreads::Integer=Threads.nthreads(),
    alignment::Integer=64,
    write_allocate::Bool=false, # TODO: compensate for write-allocates if true
)
    # check arguments
    1 ≤ N || throw(ArgumentError("N must be ≥ 1."))
    1 ≤ niter || throw(ArgumentError("niter must be ≥ 1."))
    ispow2(alignment) || throw(ArgumentError("alignment $alignment is not a power of 2"))
    alignment ≥ sizeof(Float64) ||
        throw(ArgumentError("alignment $alignment is not a multiple of $(sizeof(Float64))"))
    1 ≤ nthreads ≤ Threads.nthreads() || throw(
        ArgumentError(
            "nthreads $nthreads must ≥ 1 and ≤ $(Threads.nthreads()). If you want more threads, start Julia with a higher number of threads.",
        ),
    )

    # allocate data
    a = allocate(Float64, N, alignment)
    b = allocate(Float64, N, alignment)
    c = allocate(Float64, N, alignment)
    d = allocate(Float64, N, alignment)
    scalar = 3.0

    # initialize data
    for i in eachindex(a)
        a[i] = 2.0
        b[i] = 2.0
        c[i] = 0.5
        d[i] = 1.0
    end

    # print information
    nthreads > 1 && println("Threading enabled, using $nthreads (of $(Threads.nthreads())) Julia threads")
    if verbose
        alloc = 4.0 * sizeof(Float64) * N * 1.0e-06
        println("Total allocated datasize: $(alloc) MB")

        if Sys.islinux()
            @threads :static for i in 1:nthreads
                println("\tThread $i running on core $(get_core_id()).")
            end
        end
    end

    # perform measurement
    if nthreads == Threads.nthreads()
        # use all Julia threads, i.e. regular @threads
        times = _run_benchmark(
            init_kernel,
            copy_kernel,
            update_kernel,
            triad_kernel,
            daxpy_kernel,
            striad_kernel,
            sdaxpy_kernel,
            a,
            b,
            c,
            d,
            scalar,
            niter,
        )
    else
        # use only first `nthreads` threads, i.e. @threads for tid in 1:nthreads + manual splitting
        Nperthread = floor(Int, N / nthreads)
        rest = rem(N, nthreads)
        thread_indices = collect(Iterators.partition(1:N, Nperthread))
        if rest != 0
            # last thread compensates for the nonzero remainder
            thread_indices[end-1] = thread_indices[end-1].start:thread_indices[end].stop
        end
        times = _run_benchmark(
            init_kernel_fewer,
            copy_kernel_fewer,
            update_kernel_fewer,
            triad_kernel_fewer,
            daxpy_kernel_fewer,
            striad_kernel_fewer,
            sdaxpy_kernel_fewer,
            a,
            b,
            c,
            d,
            scalar,
            niter,
            ; thread_indices = thread_indices, nthreads = nthreads
        )
    end

    # analysis / table output of results
    results = DataFrame(;
        Function=String[],
        var"Rate (MB/s)"=Float64[],
        var"Rate (MFlop/s)"=Float64[],
        var"Avg time"=Float64[],
        var"Min time"=Float64[],
        var"Max time"=Float64[],
    )
    for j in 1:NBENCH
        # ignore the first run because of compilation
        mintime = @views minimum(times[j, 2:end])
        maxtime = @views maximum(times[j, 2:end])
        avgtime = @views mean(times[j, 2:end])
        bytes = BENCHMARKS[j].words * sizeof(Float64) * N
        flops = BENCHMARKS[j].flops * N
        data_rate = 1.0e-06 * bytes / mintime
        flop_rate = 1.0e-06 * flops / mintime
        push!(
            results, [BENCHMARKS[j].label, data_rate, flop_rate, avgtime, mintime, maxtime]
        )
    end
    verbose && pretty_table(results)

    # validation
    validate(a, b, c, d, N, niter)
    return results
end

function _run_benchmark(
    init_kernel,
    copy_kernel,
    update_kernel,
    triad_kernel,
    daxpy_kernel,
    striad_kernel,
    sdaxpy_kernel,
    a,
    b,
    c,
    d,
    scalar,
    niter,
    ; kwargs...
)
    times = zeros(NBENCH, niter)
    for k in 1:niter
        times[1, k] = @elapsed init_kernel(b, scalar; kwargs...)
        times[2, k] = @elapsed copy_kernel(c, a; kwargs...)
        times[3, k] = @elapsed update_kernel(a, scalar; kwargs...)
        times[4, k] = @elapsed triad_kernel(a, b, c, scalar; kwargs...)
        times[5, k] = @elapsed daxpy_kernel(a, b, scalar; kwargs...)
        times[6, k] = @elapsed striad_kernel(a, b, c, d; kwargs...)
        times[7, k] = @elapsed sdaxpy_kernel(a, b, c; kwargs...)
    end
    return times
end

function validate(a, b, c, d, N, niter)
    # reproduce initialization
    aj = 2.0
    bj = 2.0
    cj = 0.5
    dj = 1.0

    # now execute timing loop
    scalar = 3.0

    for k in 1:niter
        bj = scalar
        cj = aj
        aj = aj * scalar
        aj = bj + scalar * cj
        aj = aj + scalar * bj
        aj = bj + cj * dj
        aj = aj + bj * cj
    end

    aj = aj * N
    bj = bj * N
    cj = cj * N
    dj = dj * N

    asum = 0.0
    bsum = 0.0
    csum = 0.0
    dsum = 0.0

    for i in 1:N
        asum += a[i]
        bsum += b[i]
        csum += c[i]
        dsum += d[i]
    end

    epsilon = 1.e-8

    if abs(aj - asum) / asum > epsilon
        @warn("Failed Validation on array a[]: Expected $aj, Observed $asum")
        return false
    elseif abs(bj - bsum) / bsum > epsilon
        @warn("Failed Validation on array b[]: Expected $bj, Observed $bsum")
        return false
    elseif abs(cj - csum) / csum > epsilon
        @warn("Failed Validation on array c[]: Expected $cj, Observed $csum")
        return false
    elseif abs(dj - dsum) / dsum > epsilon
        @warn("Failed Validation on array d[]: Expected $dj, Observed $dsum")
        return false
    else
        return true
    end
end