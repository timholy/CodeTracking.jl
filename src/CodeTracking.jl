module CodeTracking

export whereis

# This is just a stub implementation for now
function whereis(method::Method)
    file, line = String(method.file), method.line
    if !isabspath(file)
        # This is a Base method
        file = Base.find_source_file(file)
    end
    return normpath(file), line
end

end # module
