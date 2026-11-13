local function hex(s)
    return love.data.encode("string", "hex", s)
end

return function(read_patch)
    return {
        inflate = function(raw)
            return love.data.decompress("string", "deflate", raw .. "\0\0\0\0\0\0\0\0")
        end,
        sha256 = function(s)
            return hex(love.data.hash("sha256", s))
        end,
        read_patch = read_patch,
        image = function(base, own, mask, e)
            local vd = love.image.newImageData(love.filesystem.newFileData(base, "base.png"))
            local out = love.image.newImageData(e.w, e.h)
            out:paste(vd, 0, 0, 0, 0, math.min(vd:getWidth(), e.w), math.min(vd:getHeight(), e.h))
            if own and mask then
                local od = love.image.newImageData(love.filesystem.newFileData(own, "own.png"))
                local md = love.image.newImageData(love.filesystem.newFileData(mask, "mask.png"))
                for y = 0, md:getHeight() - 1 do
                    for x = 0, md:getWidth() - 1 do
                        if md:getPixel(x, y) > 0.5 then
                            out:setPixel(e.x + x, e.y + y, od:getPixel(x, y))
                        end
                    end
                end
            end
            return out:encode("png"):getString(), hex(love.data.hash("sha256", out:getString()))
        end,
    }
end
