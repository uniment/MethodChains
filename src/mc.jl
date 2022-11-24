module Internals

export @mc

@enum(CHAIN_TYPE,
    NONCHAIN,
    SINGLE_CHAIN,                   MULTI_CHAIN,
    SINGLE_CHAIN_LINK,              MULTI_CHAIN_LINK,
    BROADCASTING_SINGLE_CHAIN,      BROADCASTING_MULTI_CHAIN,
    BROADCASTING_SINGLE_CHAIN_LINK, BROADCASTING_MULTI_CHAIN_LINK,
)

macro mc(ex)
    ex = mc(ex)
end

function mc(ex)
    esc(method_chains(ex))
end

function method_chains(ex)
    chain, type = get_chain(ex)
    if type == SINGLE_CHAIN
        ex = :(let it=$(ex.args[1]); $(single_chain(chain).args...) end)  |> clean_blocks
    elseif type == BROADCASTING_SINGLE_CHAIN
        # stuff
    elseif type == SINGLE_CHAIN_LINK
        quotedex = Expr(:quote, Symbol("$ex"))
        ex = :(it -> ($(single_chain(chain).args...))) |> clean_blocks
        ex = :(MethodChainLink{$quotedex}($ex))
    elseif type == BROADCASTING_SINGLE_CHAIN_LINK
        quotedex = Expr(:quote, Symbol("$ex"))
        ex = :(it -> broadcast(it -> ($(single_chain(chain).args...)), it)) |> clean_blocks
        ex = :(BroadcastingMethodChainLink{$quotedex}($ex))
    elseif type == MULTI_CHAIN
        ex = :(let it=$(ex.args[1]), them=(it,); $(multi_chain(chain).args...); them[1] end) |> clean_blocks
    elseif type == BROADCASTING_MULTI_CHAIN
        # stuff
    elseif type == MULTI_CHAIN_LINK
        quotedex = Expr(:quote, Symbol("$ex"))
        ex = :(it -> (them=(it,); $(multi_chain(chain).args...); them[1])) |> clean_blocks 
        ex = :(MethodMultiChainLink{$quotedex}($ex))
    elseif type == BROADCASTING_MULTI_CHAIN_LINK
        # stuff
    end

    if ex isa Expr && !is_expr(ex, :quote)
        ex.args = map(method_chains, ex.args)
    end

    ex #𝓏𝓇
end

function clean_blocks(ex)
    if is_expr(ex, :->) || is_expr(ex, :let)
        ex.args[2].args = filter(x->!(x isa LineNumberNode), ex.args[2].args)
    end
    ex
end

"""
`get_chain(ex)`

Returns what type of a chain `ex` is, and an expression whose arguments are the expressions the chain will be constructed from. 

The return value is a tuple `(chainex::Expr, type::CHAIN_TYPE)`.
"""
function get_chain(ex)
    is_expr(ex, :.) && length(ex.args) < 2 && return nothing, NONCHAIN
    # x.{y} becomes x.:({y}) so we have to cut through that
    is_expr(ex, :.) && is_expr(ex.args[2], :quote) && is_expr(ex.args[2].args[1], :braces) &&
        return ex.args[2].args[1], SINGLE_CHAIN
    #is_expr(ex, :.) && is_expr(ex.args[2], :quote) && is_expr(ex.args[2].args[1], :bracescat) && all(x->!is_expr(x, :row), ex.args[2].args[1].args) &&
    #    return ex.args[2].args[1], SINGLE_CHAIN
    is_expr(ex, :.) && is_expr(ex.args[2], :quote) && is_expr(ex.args[2].args[1], :bracescat) &&
        return ex.args[2].args[1], MULTI_CHAIN

    # Not implemented yet: Broadcasting. What's the best way to do it? Do I want to burn ' adjoint on it?
    #    return ..., BROADCASTING_SINGLE_CHAIN
    #    return ..., BROADCASTING_MULTI_CHAIN
    #is_expr(ex, :quote) && is_expr(ex.args[1], :braces) &&
    #    return ..., BROADCASTING_SINGLE_CHAIN_LINK
    #is_expr(ex, :quote) && is_expr(ex.args[1], :bracescat) &&
    #    return ..., BROADCASTING_MULTI_CHAIN_LINK
    is_expr(ex, :braces) &&
        return ex, SINGLE_CHAIN_LINK
    #is_expr(ex, :bracescat) && all(x->!is_expr(x, :row), ex.args) &&
    #    return ex, SINGLE_CHAIN_LINK
    is_expr(ex, :bracescat) &&
        return ex, MULTI_CHAIN_LINK
    nothing, NONCHAIN #𝓏𝓇
end

is_expr(ex, head) = ex isa Expr && ex.head == head

"""
`single_chain(ex)``

Take an expression whose arguments a chain will be constructed from, and return an expression where each argument is:
1. If `:it` (or `:_`, not implemented), leave out
2. If an assignment, leave as-is
3. If an expression of `it` (and not in a nested chain), change to `it=...`
4. If an assignment, a for loop, or while loop, execute and do not assign to `it`
5. If a non-callable object, such as a tuple, generator, or comprehension, simply assign to `it`
6. Otherwise, try to call it and assign to `it=`.
"""
function single_chain(ex::Expr, is_nested_in_multichain = false)
    out = Expr(:block)
    for e ∈ ex.args
        if e == :it #|| e == :_
            continue
        elseif do_not_assign_it(e)
            push!(out.args, e)
            if e == last(ex.args) push!(out.args, :it) end
        elseif has(e, :it) || is_not_callable(e) || is_nested_in_multichain && has(e, :them)
            push!(out.args, :(it = $e))
        elseif is_expr(e, :braces) || is_expr(e, :bracescat) # nested chains
            push!(out.args, method_chains(Expr(:., :it, Expr(:quote, e))))
        else
            push!(out.args, :(it = $(Expr(:call, e, :it))))
        end
    end
    isempty(out.args) && push!(out.args, :it)
    out #𝓏𝓇
end

function has(ex, s=:it) # true if ex is an expression of "it", and it isn't contained in a nested chainlink
    (ex == s || ex isa Expr && ex.head == s) && return true
    ex isa Expr || return false
    # omit sub-chainlink local scopes
    get_chain(ex)[2] ∈ (NONCHAIN, SINGLE_CHAIN, MULTI_CHAIN, BROADCASTING_MULTI_CHAIN, BROADCASTING_SINGLE_CHAIN) || return false
    for arg ∈ ex.args
        arg == s && return true
        arg isa Expr && has(arg, s) && return true
    end
    false #𝓏𝓇
end

do_not_assign_it(ex) = ex isa Expr && (ex.head ∈ (:(=), :for, :while)  )#|| ex.head == :tuple && is_expr(last(ex.args), :(=))) # this is for a,b=it; doesn't work, must parenthesize (a,b) anyway 
is_not_callable(ex) = ex isa Expr && ex.head ∈ (:(=), :for, :while, :comprehension, :generator, :tuple, :vect, :vcat, :ncat, :quote) || 
    !(ex isa Expr) && !(ex isa Symbol)
    #ex isa Number || ex isa QuoteNode || ex isa Char || ex isa String || ex isa Bool
# did I miss any?

"""
`multi_chain(ex)`

Creates parallel chains, which instantiate or collapse according to these rules:
1. If the next line has the same number of columns as the last, with no `them` slurps and no `...` splats, then append this line to all existing chains
2. Collect all values from all chains into a tuple to take inventory, and then redistribute accordingly if:
    a. the next line has more or less chains than the last, or
    b. the previous line has at least one splat `...`, or
    c. the next line has a `them`.
    - Impose that the number of splatted elements equals or is greater to the number of expressions in the next line
    - There can be multiple splats per line, but only one `them`.
    - If the previous line had a splat and the next line has a `them`, then `them` takes up all the slack and collects all extras
    - An expression `them...` both slurps and splats.
4. If the next line has more columns than the last, start a new chain
    - if there was no splat, copy the right-most chain's `it`
5. If the next line has less columns than the last, terminate chains
    - if the next line has no `them`, then discard the values of the right-most chains
    - if the next line has `them`, then any unclaimed chains are slurped into it

"""
function multi_chain(ex)
    out = Expr(:block)
    chains = Expr[]
    ex = Expr(:block, ex.args...)
    ex.args = filter(x->!(x isa LineNumberNode), ex.args) # unnecessary? maybe I'm paranoid?
    ex.args = map(x->is_expr(x, :row) ? x : Expr(:row, x), ex.args) # wrap everything in :row to make this easy

    get_row_width(row) = is_expr(row, :row) ? length(row.args) : 1
    does_splat(row) = is_expr(row, :row) && any(x->is_expr(x, :...), row.args)
    does_slurp(row) = has(row, :them)

    do_take_inventory(oldrow, newrow) = begin
        get_row_width(oldrow) ≠ get_row_width(newrow) ||
        does_splat(oldrow) ||
        has(newrow, :them)
    end

    chains = [Expr(:block, :(them[1]), e) for e ∈ ex.args[1].args]
    for (oldrow, newrow) ∈ zip(ex.args, [ex.args[2:end]; :(them[1])])
        if !(do_take_inventory(oldrow, newrow)) # new row has same # of chains as old row, so just continue chains
            for (chain, col) ∈ zip(chains, newrow.args)
                push!(chain.args, col)
            end
        else # take inventory, collect old results, start new chains
            chainsplats = [is_expr(last(c.args), :...) for c ∈ chains]  # save splats
            for c ∈ chains  # remove splats
                if is_expr(last(c.args), :...) c.args[end] = c.args[end].args[1] end
            end
            startvals = [first(c.args) for c ∈ chains]
            single_chains = [single_chain(Expr(:block, c.args[2:end]...), true) for c ∈ chains]
            chains = [clean_blocks(:(let it=$(sv); $(c.args...); end)) for (c,sv) ∈ zip(single_chains, startvals)]
            chains = [sp ? Expr(:..., ex) : ex for (ex, sp) ∈ zip(chains, chainsplats)] # restore splats

            push!(out.args, :(them = ($(chains...),)))
#            push!(out.args, :(@assert length(them) ≥ $(get_row_width(newrow)) "insufficient args (or not lol)"))

            indices = [clamp(i, 1:(does_splat(oldrow) ? typemax(Int) : length(oldrow.args))) for i = 1:length(newrow.args)]    
            chains = [Expr(:block, :(them[$i]), e) for (i,e) ∈ zip(indices, newrow.args)]
        end
    end
    out
end


end