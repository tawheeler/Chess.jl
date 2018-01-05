using Cairo
using Colors
using Vec

include("rendermodels.jl")

struct Coordinate
    i::Int
    j::Int
end
Base.getindex(arr::Matrix, loc::Coordinate) = arr[loc.i, loc.j]
Base.setindex(arr::Matrix, loc::Coordinate, val) = arr[loc.i, loc.j] = val
shift(loc::Coordinate, Δi::Int, Δj::Int) = Coordinate(loc.i + Δi, loc.j + Δj)

struct Piece
    char::Char
    white::Bool
end

const EMPTY_SQUARE = Piece('_', true)

mutable struct MailboxBoard
    pieces::Matrix{Piece}
    white_to_move::Bool
    white_could_castle::Bool # whether white is principally able to castle king- or queen side, now or later during the king
    black_could_castle::Bool # whether the involved pieces have not already been moved or in the case of rooks, were captured
    en_passant_target_square::Coordinate
    reversible_move_count::Int # number of reversible moves to keep track for the fifty-move rule
end
function MailboxBoard()
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

    return MailboxBoard(pieces,
                        true,
                        true,
                        true,
                        Coordinate(0,0),
                        0,
                        )
end

function Base.copy!(dst::MailboxBoard, src::MailboxBoard)
    copy!(dst.pieces, src.pieces)
    dst.white_to_move = src.white_to_move
    dst.white_could_castle = src.white_could_castle
    dst.black_could_castle = src.black_could_castle
    dst.en_passant_target_square = src.en_passant_target_square
    dst.reversible_move_count = src.reversible_move_count
    return dst
end
Base.copy(src::MailboxBoard) = copy!(MailboxBoard(Matrix{Piece}(8,8), true, true, true, Coordinate(0,0), 0)

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
	            add_instruction!(rendermodel, render_circle, (VecE2(x, y), PIECE_RADIUS, piece.white ? COLOR_PIECE_LIGHT : COLOR_PIECE_DARK))
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
render_highlight!(rendermodel::RenderModel, pos::Coordinate) = render_highlight!(rendermodel, pos.i, pos.j)
function render_locations!(rendermodel::RenderModel, locations::Vector{Coordinate})
	for loc in locations
		x = TILE_WIDTH*(loc.i - 0.5)
		y = TILE_WIDTH*(loc.j - 0.5)
		add_instruction!(rendermodel, render_circle, (VecE2(x, y), LOCATION_RADIUS, COLOR_HIGHLIGHT))
	end
	return rendermodel
end

function render_board(board::MailboxBoard, locations::Vector{Coordinate}=Coordinate[], highwhiteloc::Coordinate=Coordinate(0,0))
    s = CairoRGBSurface(CANVAS_WIDTH, CANVAS_HEIGHT)
    rendermodel = RenderModel()
    ctx = creategc(s)

    clear_setup!(rendermodel)
    render_tiles!(rendermodel)
    render_pieces!(rendermodel, board.pieces)
    render_locations!(rendermodel, locations)
    if highwhiteloc.i != 0
    	render_highlight!(rendermodel, highwhiteloc)
    end

    camera_set_pos!(rendermodel, 8TILE_WIDTH/2, 8TILE_WIDTH/2)
    render(rendermodel, ctx, CANVAS_WIDTH, CANVAS_HEIGHT)

    s
end

inbounds(i::Int) = 1 ≤ i ≤ 8
inbounds(loc::Coordinate) = inbounds(loc.i) && inbounds(loc.j)

isopen(board::MailboxBoard, loc::Coordinate) = board.pieces[loc].char == '_'
ismycolor(board::MailboxBoard, loc::Coordinate, mycolor::Bool) = board.pieces[loc].white == mycolor
isothercolor(board::MailboxBoard, loc::Coordinate, mycolor::Bool) = board.pieces[loc].white != mycolor
inbounds_and_open_or_other_color(board::MailboxBoard, loc::Coordinate, mycolor::Bool) = inbounds(loc) && (isopen(board, loc) || isothercolor(board, loc, mycolor))

"""
Get all legal moves irrespective of whether you end up in check
"""
function get_pseudo_legal_moves_knight(board::MailboxBoard, loc::Coordinate, white::Bool)
    i,j = loc.i, loc.j
    return filter!(p -> inbounds_and_open_or_other_color(board, p, white), [
        Coordinate(i+2,j+1),
        Coordinate(i+2,j-1),
        Coordinate(i-2,j+1),
        Coordinate(i-2,j-1),
        Coordinate(i+1,j+2),
        Coordinate(i-1,j+2),
        Coordinate(i+1,j-2),
        Coordinate(i-1,j-2),
    ])
end
function get_pseudo_legal_moves_bishop(board::MailboxBoard, loc::Coordinate, white::Bool)
    coordinates = Coordinate[]
	for dx in (-1,1)
		for dy in (-1,1)
			Δx = dx
			Δy = dy
			while inbounds_and_open_or_other_color(board, shift(loc, Δx, Δy), white)
				push!(coordinates, shift(loc, Δx, Δy))
				Δx += dx
				Δy += dy
			end
		end
	end
	return coordinates
end
function get_pseudo_legal_moves_rook(board::MailboxBoard, loc::Coordinate, white::Bool)
    coordinates = Coordinate[]
	for (dx,dy) in [(-1,0), (0,-1), (1,0), (0,1)]
		Δx = dx
		Δy = dy
		while inbounds_and_open_or_other_color(board, shift(loc, Δx, Δy), white)
			push!(coordinates, shift(loc, Δx, Δy))
			Δx += dx
			Δy += dy
		end
	end
	return pieces
end
function get_pseudo_legal_moves_queen(board::MailboxBoard, loc::Coordinate, white::Bool)
	append!(
		get_pseudo_legal_moves_bishop(board, loc, white),
		get_pseudo_legal_moves_rook(board, loc, white),
		)
end
function get_pseudo_legal_moves_king(board::MailboxBoard, loc::Coordinate, white::Bool)
	i,j = loc.i, loc.j
    return filter!(p -> inbounds_and_open_or_other_color(board, p, white), [
	    Coordinate(i+1,j+1),
	    Coordinate(i+1,j-1),
	    Coordinate(i-1,j+1),
	    Coordinate(i-1,j-1),
	    Coordinate(i+1,j+1),
	    Coordinate(i-1,j+1),
	    Coordinate(i+1,j-1),
	    Coordinate(i-1,j-1),
	])
end
function get_pseudo_legal_moves_pawn(board::MailboxBoard, loc::Coordinate, white::Bool)
    dy = white ? 1 : -1
	coordinates = Coordinate[]

    loc_push = shift(loc, 0, dy)
	if inbounds(loc_push) && isopen(board, loc_push)
		push!(coordinates, loc_push)
		if (loc.j == (white ? 2 : 7)) && isopen(board, shift(loc, 0, 2dy))
			push!(coordinates, shift(loc, 0, 2dy))
		end
	end
	for dx in (-1,1)
        newloc = shift(loc, dx, dy)
		if (loc.j == (white ? 2 : 7)) && inbounds(newloc) && isothercolor(board, newloc, white)
			push!(coordinates, newloc)
		end
	end
	return coordinates
end
function get_pseudo_legal_moves(board::MailboxBoard, loc::Coordinate)
	piece = board.pieces[loc]
	if piece.char == 'N'
		return get_pseudo_legal_moves_knight(board, loc, piece.white)
	elseif piece.char == 'B'
		return get_pseudo_legal_moves_bishop(board, loc, piece.white)
	elseif piece.char == 'R'
		return get_pseudo_legal_moves_rook(board, loc, piece.white)
	elseif piece.char == 'Q'
		return get_pseudo_legal_moves_queen(board, loc, piece.white)
	elseif piece.char == 'K'
		return get_pseudo_legal_moves_king(board, loc, piece.white)
	elseif piece.char == 'P'
		return get_pseudo_legal_moves_pawn(board, loc, piece.white)
	else
		return Tuple{Int,Int}[]
	end
end

"""
    Moves piece at src to coordiante dst.

    Special cases:
        - castling is represented using the king's move src → dst
        - pawn promotion sets the promotion field

    quiet move := does not alter material
    capture := takes a piece
    promotion := pawn to new
"""
struct Move
    src::Coordinate # source coordinate
    dst::Coordinate # target coordinate
    promotion::Char # what a promoted pawn becomes
end
Move(src::Coordinate, dst::Coordinate) = Move(src, dst, '')

"""
reversible moves increment the clock for use with the fifty-move rule.
All moves by non-pawns to empty target squares.
"""
is_reversible(board::MailboxBoard, move::Move) = board.pieces[move.src].char != 'P' && board.pieces[move.dst].char == '_'

function make_move(board::MailboxBoard, move::Move)
    retval = copy(board) # NOTE: this allocates memory
    if board.pieces[move.src].char == 'P'
        # pawn
    elseif board.pieces[move.src].char == 'K' && abs(a.i - b.i) > 1
        # castle
        
    else
        board[move.dst] = board[move.src]
        board[move.src] = EMPTY_SQUARE
    end
    return board
end

# function get_unconstrained_check_map(board::MailboxBoard, mycolor::Bool)
# 	checkmap = falses(8,8)
# 	for i in 1 : 8
# 		for j in 1 : 8
# 			if ismycolor(board, i, j, mycolor)
# 				for loc in get_pseudo_legal_moves(board, i, j)
# 					checkmap[loc...] = true
# 				end
# 			end
# 		end
# 	end
# 	return checkmap
# end