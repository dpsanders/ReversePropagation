# Reverse interval constraint propagation using Symbolics


# import Base: ⊓
# import Base: ⊔


#

⊔
⊔

# @register a ⊓ b
# @register a ⊔ b

# Possibly should replace all calls to `rev` with calls to the actual
# reverse functions instead for speed


function remove_constant(s)
    value = Symbolics.value(s)
    return (value isa Real || value isa Sym) ? variable(:_) : value
end

remove_parameters(s, params) = (any(x -> isequal(x, s), params)) ? variable(:_) : s

function rev(eq::Assignment, params)

    vars = tuple(args(eq)...)
    return_vars = remove_constant.(tuple(lhs(eq), vars...))
    # return_vars = remove_constant.(tuple(lhs(eq), vars...))

    return_vars = remove_parameters.(return_vars, Ref(params))

    reverse = rev(op(eq), lhs(eq), vars...)

    return Assignment(Symbolics.MakeTuple(return_vars), reverse)

end


# difference between reverse mode AD and reverse propagation:
# reverse mode AD introduces *new* variables
# reverse propagation can use the *same* variables

# x ~ x ⊓ (z - y)


# reverse ops from IntervalContractors:


const binary_functions = Dict(
                    :+     => :plus_rev,
                    :-     => :minus_rev,
                    :*     => :mul_rev,
                    :/     => :div_rev,
                    :^     => :power_rev,
                    );

for (f, f_rev) in binary_functions
    @eval rev(::typeof($f), z::Real, x::Real, y::Real) = $f_rev(z, x, y) 
    @eval @register_symbolic rev(a::typeof($f), z, x, y) false
end


const unary_functions = [:sqrt, :abs,
            :exp, :exp2, :exp10, :expm1,
            :log, :log2, :log10, :log1p,
            :sin, :cos, :tan,
            :asin, :acos, :atan,
            :sinh, :cosh, :tanh,
            :asinh, :acosh, :atanh,
            :inv, :sign, :max, :min];

for f in unary_functions
    f_rev = Symbol(f, :_rev)
    @eval rev(::typeof($f), z::Real, x::Real) = $f_rev(z, x)
    @eval @register_symbolic rev(a::typeof($f), z::Real, x::Real) false
end


"Generate code (as Symbolics.Assignment) for forward--backward (HC4Revise) contractor"
function forward_backward_code(ex, vars, params=[])

    final_var = make_variable(:value)  # to record the output of running the forward interval function
    constraint_var = make_variable(:constraint)   # symbolic constraint variable

    forward_code, last = cse_equations(ex)

    # @show forward_code


    # @show constraint_var, final_var

    constraint_code = [Assignment(final_var, last),
                        Assignment(last, last ⊓ constraint_var)]

    reverse_code = rev.(reverse(forward_code), Ref(params))


    code = [forward_code; constraint_code; reverse_code]

    return code, final_var, constraint_var
end

# code, final, constraint = forward_backward_code(x^2 + a*y^2, [x, y], [a])

# code

Symbolics.toexpr(t::Tuple) = Symbolics.toexpr(Symbolics.MakeTuple(t))

# vars = @variables x, y

# ex = x^2 + a*y^2
# code, final, constraint = forward_backward_code(ex, vars, [a])

# code
# final
# constraint

# dump(toexpr.(code))

# function forward_backward_expr(vars, ex)
#     symbolic_code, final, constraint = forward_backward_code(vars, ex)

#     code = toexpr.(symbolic_code)

#     return_tuple = toexpr(vars)
#     # push!(code.args, :(return $return_tuple))

#     return code, final, return_tuple
# end

"Build Julia code for forward_backward contractor"
function forward_backward_expr(ex, vars, params=[])

    symbolic_code, final_var, constraint_var = forward_backward_code(ex, vars, params)

    # @show symbolic_code

    code = toexpr.(symbolic_code)
    all_code = Expr(:block, code...)

    return all_code, final_var, constraint_var
end


# forward_backward_expr(ex, vars, [a])


function forward_backward_contractor(ex, vars, params=[])

    code, final_var, constraint_var = forward_backward_expr(ex, vars, params)

    input_vars = toexpr(Symbolics.MakeTuple(vars))
    final = toexpr(final_var)

    constraint = toexpr(constraint_var)

    if !isempty(params)
        params_tuple = toexpr(Symbolics.MakeTuple(params))

        function_code =
            quote
                ($input_vars, $constraint, $params_tuple) -> begin
                    $code
                    return $input_vars, $(final)
                end
            end

    else

        function_code =
            quote
                ($input_vars, $constraint) -> begin
                    $code
                    return $input_vars, $(final)
                end
            end

    end

    return eval(function_code)


end

# ex = x^2 + a * y^2
# C = forward_backward_contractor(ex, vars, [a])

# const CC2 = forward_backward_contractor(ex, vars, [a])

# CC2((-10..10, -10..10), 0..1, 5)
# @btime CC2((-10..10, -10..10), 0..1, 6)
# @btime CC2((-10..10, -10..10), 0..1, 7)


# using BenchmarkTools

# @btime CC((-10..10, -10..10), 0..1)

# @code_native C((-10..10, -10..10), 0..1)

# CC(IntervalBox(-10..10, 2), 0..1)



# vars = @variables x, y
# ex = 3x^2 + 4x^2 * y


# code, final, return_tuple = forward_backward_code(vars, 3x^2 + 4x^2 * y)

# expr = forward_backward_expr(vars, ex)

# C = forward_backward_contractor(vars, ex)


# using IntervalArithmetic

# C( (1..2, 3..4) )

# ex = x^2 + y^2

# C( (-10..10, -10..10) )
