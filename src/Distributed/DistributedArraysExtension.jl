"""
Fetches a distributed slice of a distributed array
"""
function fetch_distributedslice(d::DArray, i1, i2; M=Matrix{eltype(d)}(undef, i2-i1+1, size(d, 2)))
    rs = Vector{MPIFuture}(undef, length(d.pids))

    for (i, (idx, w)) in enumerate(zip(d.indices, d.pids))
        dest = @view M[:, idx[2]]
        rs[i] = remotecall_mpi!(dest, d->d.localpart[i1:i2, :], w, d)
    end
    wait.(rs)
    return M
end

"""
Fetches a distributed slice of a distributed array and multiplies it with its transpose
"""
function fetch_and_multiply(d, i1, i2)
    M = fetch_distributedslice(d, i1, i2)
    return M' * M
end

"""
Calculates d' * d where d is a distributed array
"""
function self_mul_transpose(d::DArray)
    rs = Vector{Future}(undef, length(d.pids))
    i1 = 1
    nr_k = size(d, 1)
    nr_k_i = nr_k ÷ length(d.pids)
    for (i, w) in enumerate(d.pids)
        i2 = i1 + nr_k_i -1
        rs[i] = Distributed.remotecall(fetch_and_multiply, w, d, i1, i2)
        i1 = i2 + 1
    end

    sum_ = zeros(eltype(d), size(d, 2), size(d, 2))
    for r in rs
        sum_ .+= fetch(r)
    end
    return sum_
end