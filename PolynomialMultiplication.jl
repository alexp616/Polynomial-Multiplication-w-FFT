using BenchmarkTools
using Profile
using CUDA
using Test

function slowMultiply(polynomial1, polynomial2)
    # Classic, O(n^2) way of multiplying polynomials (FOIL)
    # 
    # Parameter definitions:
    # polynomial1, polynomial2: Arrays containing coefficients of polynomials to be multiplied.
    # 
    # Returns array containing coefficients of product of polynomial1 and polynomial2

    temp = fill(0, length(polynomial1) + length(polynomial2)-1)
    for i in eachindex(polynomial1) 
        for j in eachindex(polynomial2)
            @inbounds temp[i + j - 1] += polynomial1[i] * polynomial2[j]
        end
    end
    return temp
    
end

# RECURSIVE DFT
# 
# 
# 
# 
# 

function recursiveDFT(a, inverted = 1)
    # Parent function to call fastDFThelper, only exists so that this theta array only needs to be calculated once
    #
    # Parameter definition:
    # a: coefficients of polynomial to be evaluated
    # inverted: default to 1, useful in inverseDFT algorithm.
    #
    # Returns coefficients of y, evaluated by Va=y

    theta = [cis(2 * (i - 1) * inverted * pi / length(a)) for i in 1:div(length(a), 2)]
    return recursiveDFThelper(a, theta, 0, inverted)
end

function recursiveDFThelper(a, theta, depth = 0, inverted = 1)
    # First step of FFT. Evaluates polynomial with coefficients stored in a at the n roots of unity, where
    # n = 2^ceiling(log_2(final degree of product)). We want n to be a power of 2, because it makes the recursion
    # easy. 
    # 
    # Parameter definition:
    #
    # a: coefficients of polynomial to be evaluated
    # inverted: default to 1, useful when calling fastIDFT() because DFT and IDFT are basically the same algorithm
    # 
    # Returns coefficients of y, evaluated by Va=y

    n = length(a)
    if n == 1 return a
    end

    # Slicing up polynomial for p(x) = p0(x^2) + xp1(x^2)
    a0 = a[1:2:n]
    a1 = a[2:2:n]

    # Recursive step, this is what makes the algorithm nlog(n)
    y0 = recursiveDFThelper(a0, theta, depth + 1, inverted)
    y1 = recursiveDFThelper(a1, theta, depth + 1, inverted)

    # Initializing final array
    result = fill(ComplexF32(0), n)

    for i in 1:div(n, 2)
        # p(x) = p0(x^2) + xp1(x^2)
        @inbounds result[i] = y0[i] + theta[(2^depth) * (i - 1) + 1] * y1[i]
        @inbounds result[i + div(n, 2)] = y0[i] - theta[(2^depth) * (i - 1) + 1] * y1[i]
    end

    return result
end


function recursiveIDFT(y)
    # InverseDFT. DFT is the transformation represented by Va=y, where V is the Vandermonde matrix consisting of 
    # the n roots of unity. IDFT calculates a=V^-1 y, and V^-1 is very easy to calculate.
    # 
    # Parameter definition:
    # y: coefficients of vector generated by evaluating polynomial at n roots of unity
    # 
    # Returns array containing coefficients of polynomial that generated y from Va=y

    n = length(y)
    result = recursiveDFT(y, -1)
    return [result[i] / n for i in eachindex(result)]
end

function recursiveMultiply(p1, p2)
    # Extremely quick explanation of multiplying polynomials with DFT:
    # Let a and b be arrays that represent the coefficients of the polynomial. Then, the Vandermonde matrix V
    # evaluates a and b at the n roots of unity, where n is the next highest power of 2 of the resulting product degree
    # So, Va = y, and Vb = z. Multiplying the corresponding entries of y and z, to result in vector x, yields the product
    # evaluated at the n roots of unity. Then, our final polynomial, c, can be computed by c = V^-1 z.
    # 
    # Parameter definitions:
    # 
    # polynomial1, polynomial2: Arrays containing coefficients of polynomials to be multiplied. Copies of these arrays are
    # created so that the originals are unchanged.
    #
    # Returns array containing coefficients of product of polynomial1 and polynomial2

    n = Int.(2^ceil(log2(length(p1) + length(p2) - 1)))
    finalLength = length(p1) + length(p2) - 1

    copyp1 = copy(p1)
    copyp2 = copy(p2)

    append!(copyp1, zeros(Int, n - length(p1)))
    append!(copyp2, zeros(Int, n - length(p2)))

    y1 = recursiveDFT(copyp1)
    y2 = recursiveDFT(copyp2)

    ans = recursiveIDFT([y1[i] * y2[i] for i in 1:n])
    return [round(Int, real(ans[i])) for i in 1:finalLength]
end

# ITERATIVE DFT
# 
# 
# 
# 
# 

function bitReverse(x, log2n)
    temp = 0
    for i in 0:log2n-1
        temp <<= 1
        temp |= (x & 1)
        x >>= 1
    end
    return temp
end 

# Honestly don't understand how this works yet, basically copied from
# https://www.geeksforgeeks.org/iterative-fast-fourier-transformation-polynomial-multiplication/
function iterativeDFT(p, inverted = 1)
    n = length(p)
    log2n = UInt32(log2(n));
    result = fill(ComplexF32(0), n)

    for i in 0:n-1
        rev = bitReverse(i, log2n)
        @inbounds result[i+1] = p[rev+1]
    end

    for i in 1:log2n
        m = 1 << i
        m2 = m >> 1
        theta = complex(1,0)
        theta_m = cis(inverted * pi/m2)
        for j in 0:m2-1
            for k in j:m:n-1
                t = theta * result[k + m2 + 1]
                u = result[k + 1]

                result[k + 1] = u + t
                result[k + m2 + 1] = u - t
            end
            theta *= theta_m
        end
    end

    return result
end

function iterativeIDFT(y)
    # InverseDFT. DFT is the transformation represented by Va=y, where V is the Vandermonde matrix consisting of 
    # the n roots of unity. IDFT calculates a=V^-1 y, and V^-1 is very easy to calculate.
    # Parameter definition:
    #
    # y: coefficients of vector generated by evaluating polynomial at n roots of unity
    # 
    # Returns array containing coefficients of polynomial that generated y from Va=y

    n = length(y)
    result = iterativeDFT(y, -1)
    return [result[i] / n for i in eachindex(result)]
end

function iterativeMultiply(p1, p2)
    # Extremely quick explanation of multiplying polynomials with DFT:
    # Let a and b be arrays that represent the coefficients of the polynomial. Then, the Vandermonde matrix V
    # evaluates a and b at the n roots of unity, where n is the next highest power of 2 of the resulting product degree
    # So, Va = y, and Vb = z. Multiplying the corresponding entries of y and z, to result in vector x, yields the product
    # evaluated at the n roots of unity. Then, our final polynomial, c, can be computed by c = V^-1 z.
    # 
    # Parameter definitions:
    # 
    # polynomial1, polynomial2: Arrays containing coefficients of polynomials to be multiplied. Copies of these arrays are
    # created so that the originals are unchanged.
    #
    # Returns array containing coefficients of product of polynomial1 and polynomial2

    n = Int.(2^ceil(log2(length(p1) + length(p2) - 1)))
    finalLength = length(p1) + length(p2) - 1

    copyp1 = copy(p1)
    copyp2 = copy(p2)

    append!(copyp1, zeros(Int, n - length(p1)))
    append!(copyp2, zeros(Int, n - length(p2)))

    y1 = iterativeDFT(copyp1)
    y2 = iterativeDFT(copyp2)

    ans = iterativeIDFT([y1[i] * y2[i] for i in 1:n])
    return [round(Int, real(ans[i])) for i in 1:finalLength]
end

# GPU-PARALLELIZED-VERSION
#
#
#
#
#

function gpuFFT(p::CuArray{ComplexF32}, inverted = 1)
    n = length(p)
    twiddle = CUDA.fill(ComplexF32(0), n)
    result = CUDA.fill(ComplexF32(0), n)
    
    nthreads = min(CUDA.attribute(
        device(),
        CUDA.DEVICE_ATTRIBUTE_MAX_THREADS_PER_BLOCK
    ), n)

    nblocks = cld(n, nthreads)

    @cuda threads=nthreads blocks=nblocks compute_twiddle_factors(twiddle, n, inverted)
    
    @cuda threads=nthreads blocks=nblocks parallel_fft_butterfly(p, twiddle, result, n)

    return result
end

function compute_twiddle_factors(twiddle, n, inverted)
    idx = threadIdx().x + (blockIdx().x - 1) * blockDim().x
    if idx <= n
        twiddle[idx] = cis(inverted * 2 * pi * (idx - 1) / n)
    end
    return
end

function parallel_fft_butterfly(input, twiddle, output, n)
    idx = threadIdx().x + (blockIdx().x - 1) * blockDim().x
    if idx <= n
        sum = ComplexF32(0)
        for k = 1:n
            sum += input[k] * twiddle[((idx - 1) * (k - 1)) % n + 1]
        end
        output[idx] = sum
    end
    return
end

function gpuIFFT(p::CuArray{ComplexF32})
    return gpuFFT(p, -1) .*  (1/length(p))
end

function gpuMultiply(p1, p2)
    n = Int.(2^ceil(log2(length(p1) + length(p2) - 1)))
    finalLength = length(p1) + length(p2) - 1

    # TODO surely there must be a better way to do this
    copyp1 = append!(convert(Array{ComplexF32}, copy(p1)), zeros(ComplexF32, n - length(p1)))
    copyp2 = append!(convert(Array{ComplexF32}, copy(p2)), zeros(ComplexF32, n - length(p2)))

    y1 = gpuFFT(CuArray(copyp1))
    y2 = gpuFFT(CuArray(copyp2))

    ans = Array(gpuIFFT(y1 .* y2))
    return [round(Int, real(ans[i])) for i in 1:finalLength]
end

# SQUARING & POWERS
#
#
#
#
#

# TODO figure out how to optimize this
function polynomialSquare(p)
    return iterativeMultiply(p, p)
end

function toBits(n)
    bits = [0 for i in 1:ceil(log2(n))]
    for i in eachindex(bits)
        bits[i] = n & 1
        n >>= 1
    end
    return bits
end

function polynomialPow(p, n)
    # Only takes positive integer n>=1
    bitarr = toBits(n)
    result = [1]
    temp = p
    for i in 1:length(bitarr)-1
        if i == 1
            result = iterativeMultiply(result, temp)
        temp = polynomialSquare(temp)
        end
    end
    if bitarr[end] == 1
        result = iterativeMultiply(result, temp)
    end
    return result
end

polynomial1 = [1 for i in 1:2^10]
polynomial2 = [1 for i in 1:2^10]

# potential of precision errors when degree gets too high
println("-----------------start------------------")
# the gpu algorithms are faster when the Cuda Array is already initialized. However,
# there is a HUGE overhead for creating the cuda array which makes the non-parallelized
# algorithms faster until a very very high degree


cudaarray = CuArray(convert(Array{ComplexF32}, polynomial1))
# gpuFFT is faster
@btime gpuFFT(cudaarray)
@btime iterativeDFT(polynomial1)

# Forward FFT works
@test Array(gpuFFT(cudaarray)) == iterativeDFT(polynomial1)

# gpuIFFT is faster
@btime gpuIFFT(cudaarray)
@btime iterativeIDFT(polynomial1)

@test Array(gpuIFFT(cudaarray)) == iterativeIDFT(polynomial1)
println("------------------end-------------------")


