using Cairo
using Colors
using Vec

include(Pkg.dir("AutoViz", "src", "rendermodels.jl"))

struct Piece
    char::Char
    light::Bool
end
mutable struct Board
    pieces::Matrix{Piece}
    light_castled::Bool
    dark_castled::Bool
end
function Board()
    pieces = Array{Piece}(8, 8)
    for i in 1 : 64
        pieces[i] = Piece('_', true)
    end
    for i in 1 : 8
        pieces[i,2] = Piece('P', true)
        pieces[i,7] = Piece('P', false)
    end
    pieces[1,1] = Piece('R', true)
    pieces[2,1] = Piece('N', true)
    pieces[3,1] = Piece('B', true)
    pieces[4,1] = Piece('Q', true)
    pieces[5,1] = Piece('K', true)
    pieces[6,1] = Piece('B', true)
    pieces[7,1] = Piece('N', true)
    pieces[8,1] = Piece('R', true)
    pieces[1,8] = Piece('R', false)
    pieces[2,8] = Piece('N', false)
    pieces[3,8] = Piece('B', false)
    pieces[4,8] = Piece('Q', false)
    pieces[5,8] = Piece('K', false)
    pieces[6,8] = Piece('B', false)
    pieces[7,8] = Piece('N', false)
    pieces[8,8] = Piece('R', false)

    return Board(pieces, false, false)
end

const CANVAS_WIDTH = 300
const CANVAS_HEIGHT = CANVAS_WIDTH

const TILE_WIDTH = CANVAS_WIDTH/8
const PIECE_RADIUS = TILE_WIDTH*0.3
const PIECE_FONT_SIZE = 15
const LOCATION_RADIUS = TILE_WIDTH*0.45

const COLOR_TILE_LIGHT = colorant"blue"
const COLOR_TILE_DARK = colorant"black"

const COLOR_PIECE_LIGHT = colorant"red"
const COLOR_PIECE_DARK = colorant"green"
const COLOR_HIGHLIGHT = RGBA(1.0,1.0,1.0,0.6)
const COLOR_TEXT = colorant"white"

function render_tiles!(rendermodel::RenderModel)
	for i in 1 : 8
	    for j in 1 : 8
	        add_instruction!(rendermodel, render_rect, (VecE2(TILE_WIDTH*(i - 0.5), TILE_WIDTH*(j - 0.5)),
	        											TILE_WIDTH, TILE_WIDTH,
	        											mod(i + j, 2) == 1 ? COLOR_TILE_LIGHT : COLOR_TILE_DARK))
	    end
	end
	return rendermodel
end
function render_pieces!(rendermodel::RenderModel, pieces::Matrix{Piece})
	for i in 1 : 8
	    for j in 1 : 8
	        piece = pieces[i,j]
	        if piece.char != '_'
	            x = TILE_WIDTH*(i - 0.5)
	            y = TILE_WIDTH*(j - 0.5)
	            add_instruction!(rendermodel, render_circle, (VecE2(x, y), PIECE_RADIUS, piece.light ? COLOR_PIECE_LIGHT : COLOR_PIECE_DARK))
	            add_instruction!(rendermodel, render_text, (string(piece.char), x, y, PIECE_FONT_SIZE, COLOR_TEXT, true))
	        end
	    end
	end
	return rendermodel
end

function render_highlight!(rendermodel::RenderModel, i::Int, j::Int)
	x = TILE_WIDTH*(i - 0.5)
	y = TILE_WIDTH*(j - 0.5)
	add_instruction!(rendermodel, render_circle, (VecE2(x, y), PIECE_RADIUS, COLOR_HIGHLIGHT))
	return rendermodel
end
function render_locations!(rendermodel::RenderModel, locations::Vector{Tuple{Int,Int}})
	for (i,j) in locations
		x = TILE_WIDTH*(i - 0.5)
		y = TILE_WIDTH*(j - 0.5)
		add_instruction!(rendermodel, render_circle, (VecE2(x, y), LOCATION_RADIUS, COLOR_HIGHLIGHT))
	end
	return rendermodel
end

function render_board(board::Board, locations::Vector{Tuple{Int,Int}}=Tuple{Int,Int}[], highlightloc::Tuple{Int,Int}=(0,0))
    s = CairoRGBSurface(CANVAS_WIDTH, CANVAS_HEIGHT)
    rendermodel = RenderModel()
    ctx = creategc(s)

    clear_setup!(rendermodel)
    render_tiles!(rendermodel)
    render_pieces!(rendermodel, board.pieces)
    render_locations!(rendermodel, locations)
    if highlightloc[1] != 0
    	render_highlight!(rendermodel, highlightloc...)
    end

    camera_set_pos!(rendermodel, 8TILE_WIDTH/2, 8TILE_WIDTH/2)
    render(rendermodel, ctx, CANVAS_WIDTH, CANVAS_HEIGHT)

    s
end

inbounds(i::Int) = 1 ≤ i ≤ 8
inbounds(i::Int, j::Int) = inbounds(i) && inbounds(j)

isopen(board::Board, i::Int, j::Int) = board.pieces[i,j].char == '_'
ismycolor(board::Board, i::Int, j::Int, mycolor::Bool) = board.pieces[i,j].light == mycolor
isothercolor(board::Board, i::Int, j::Int, mycolor::Bool) = board.pieces[i,j].light != mycolor
inbounds_and_open_or_other_color(board::Board, i::Int, j::Int, mycolor::Bool) = inbounds(i,j) && (isopen(board, i, j) || isothercolor(board, i, j, mycolor))

"""
Get all legal moves irrespective of whether you end up in check
"""
function get_unconstrained_actions_knight(board::Board, i::Int, j::Int, light::Bool)
    return filter!(p -> inbounds_and_open_or_other_color(board, p[1], p[2], light), [
        (i+2,j+1),
        (i+2,j-1),
        (i-2,j+1),
        (i-2,j-1),
        (i+1,j+2),
        (i-1,j+2),
        (i+1,j-2),
        (i-1,j-2),
    ])
end
function get_unconstrained_actions_bishop(board::Board, i::Int, j::Int, light::Bool)
	pieces = Tuple{Int,Int}[]
	for dx in (-1,1)
		for dy in (-1,1)
			Δx = dx
			Δy = dy
			while inbounds_and_open_or_other_color(board, i+Δx, j+Δy, light)
				push!(pieces, (i+Δx, j+Δy))
				Δx += dx
				Δy += dy
			end
		end
	end
	return pieces
end
function get_unconstrained_actions_rook(board::Board, i::Int, j::Int, light::Bool)
	pieces = Tuple{Int,Int}[]
	for (dx,dy) in [(-1,0), (0,-1), (1,0), (0,1)]
		Δx = dx
		Δy = dy
		while inbounds_and_open_or_other_color(board, i+Δx, j+Δy, light)
			push!(pieces, (i+Δx, j+Δy))
			Δx += dx
			Δy += dy
		end
	end
	return pieces
end
function get_unconstrained_actions_queen(board::Board, i::Int, j::Int, light::Bool)
	vcat(
		get_unconstrained_actions_bishop(board, i, j, light),
		get_unconstrained_actions_rook(board, i, j, light),
		)
end
function get_unconstrained_actions_king(board::Board, i::Int, j::Int, light::Bool)
	return filter!(p -> inbounds_and_open_or_other_color(board, p[1], p[2], light), [
	    (i+1,j+1),
	    (i+1,j-1),
	    (i-1,j+1),
	    (i-1,j-1),
	    (i+1,j+1),
	    (i-1,j+1),
	    (i+1,j-1),
	    (i-1,j-1),
	])
end
function get_unconstrained_actions_pawn(board::Board, i::Int, j::Int, light::Bool)
	dy = light ? 1 : -1
	retval = Tuple{Int,Int}[]
	if inbounds(i,j+dy) && isopen(board, i, j+dy)
		push!(retval, (i, j+dy))
		if (j == (light ? 2 : 7)) && isopen(board, i, j+2dy)
			push!(retval, (i, j+2dy))
		end
	end
	for dx in (-1,1)
		if (j == (light ? 2 : 7)) && inbounds(i+dx,j+dy) && isothercolor(board, i+dx, j+dy, light)
			push!(retval, (i+dx, j+dy))
		end
	end
	return retval
end
function get_unconstrained_actions(board::Board, i::Int, j::Int)
	piece = board.pieces[i,j]
	if piece.char == 'N'
		return get_unconstrained_actions_knight(board, i, j, piece.light)
	elseif piece.char == 'B'
		return get_unconstrained_actions_bishop(board, i, j, piece.light)
	elseif piece.char == 'R'
		return get_unconstrained_actions_rook(board, i, j, piece.light)
	elseif piece.char == 'Q'
		return get_unconstrained_actions_queen(board, i, j, piece.light)
	elseif piece.char == 'K'
		return get_unconstrained_actions_king(board, i, j, piece.light)
	elseif piece.char == 'P'
		return get_unconstrained_actions_pawn(board, i, j, piece.light)
	else
		return Tuple{Int,Int}[]
	end
end

# function get_unconstrained_check_map(board::Board, mycolor::Bool)
# 	checkmap = falses(8,8)
# 	for i in 1 : 8
# 		for j in 1 : 8
# 			if ismycolor(board, i, j, mycolor)
# 				for loc in get_unconstrained_actions(board, i, j)
# 					checkmap[loc...] = true
# 				end
# 			end
# 		end
# 	end
# 	return checkmap
# end