using Cairo
using Colors
using Vec
using Base.Test

include("rendermodels.jl")

struct Coordinate
    i::Int
    j::Int
end
Base.getindex(arr::Matrix, loc::Coordinate) = arr[loc.i, loc.j]
Base.setindex!(arr::Matrix, val, loc::Coordinate) = arr[loc.i, loc.j] = val
shift(loc::Coordinate, Δi::Int, Δj::Int) = Coordinate(loc.i + Δi, loc.j + Δj)

struct Piece
    char::Char
    white::Bool
end

const EMPTY_SQUARE = Piece('_', true)

mutable struct MailboxBoard
    pieces::Matrix{Piece}
    white_to_move::Bool
    white_could_castle_kingside::Bool # whether white is principally able to castle king- or queen side, now or later during the king
    white_could_castle_queenside::Bool # whether the involved pieces have not already been moved or in the case of rooks, were captured
    black_could_castle_kingside::Bool
    black_could_castle_queenside::Bool
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
                        true,
                        true,
                        Coordinate(0,0),
                        0,
                        )
end

function Base.copy!(dst::MailboxBoard, src::MailboxBoard)
    copy!(dst.pieces, src.pieces)
    dst.white_to_move = src.white_to_move
    dst.white_could_castle_kingside = src.white_could_castle_kingside
    dst.white_could_castle_queenside = src.white_could_castle_queenside
    dst.black_could_castle_kingside = src.black_could_castle_kingside
    dst.black_could_castle_queenside = src.black_could_castle_queenside
    dst.en_passant_target_square = src.en_passant_target_square
    dst.reversible_move_count = src.reversible_move_count
    return dst
end
Base.copy(src::MailboxBoard) = copy!(MailboxBoard(Matrix{Piece}(8,8), true, true, true, true, true, Coordinate(0,0), 0), src)

function Base.hash(board::MailboxBoard, h::UInt64=zero(UInt64))
    return hash(board.pieces,
            hash(board.white_to_move,
                hash(board.white_could_castle_kingside,
                    hash(board.white_could_castle_queenside,
                        hash(board.black_could_castle_kingside,
                            hash(board.black_could_castle_queenside,
                                hash(board.en_passant_target_square,
                                    hash(board.reversible_move_count, h))))))))
end

"""
The board notation starts at a1 and lists each row.
White pieces are lowercase and black pieces are uppercase.
A digit indicates the number of empty spaces to skip.
This is followed by some stuff that may indicate who moves (w/b), castling rights for king and queenside (KQkq), and two digits whose meaning I don't know

ex: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1
ex: "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10"
ex: "r3k2r/p1ppqb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -
"""
function to_board_notation(board::MailboxBoard)
    retval = ""
    for j in 1 : 8
        digit_count = 0
        for i in 1 : 8
            if board.pieces[i,j].char == '_'
                digit_count += 1
            else
                if digit_count > 0
                    retval *= string(digit_count)
                    digit_count = 0
                end
                piece = board.pieces[i,j]
                retval *= piece.white ? lowercase(piece.char) : uppercase(piece.char)
            end
        end

        if digit_count > 0
            retval *= string(digit_count)
        end
        if j < 8
            retval *= "/"
        end
    end
    retval *= " " * (board.white_to_move ? "w" : "b")

    castle_string = " "
    if board.white_could_castle_kingside; castle_string *= "K"; end
    if board.white_could_castle_queenside; castle_string *= "Q"; end
    if board.black_could_castle_kingside; castle_string *= "k"; end
    if board.black_could_castle_queenside; castle_string *= "q"; end
    retval *= (castle_string == " " ? " -" : castle_string)
    retval *= " - 0 1" # not sure what to put here (file of en passant pawn and reversible move count?)
    return retval
end
const STARTING_BOARD = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
@test to_board_notation(MailboxBoard()) == STARTING_BOARD

Piece(char::Char) = Piece(uppercase(char), char > 'Z')

function MailboxBoard(board_notation::String)
    pieces = Array{Piece}(8, 8)
    i, j, k = 1, 1, 1
    while 8(j-1) + (i-1) < 64
        c = board_notation[k]
        if '1' ≤ c ≤ '8'
            while c > '0'
                pieces[i,j] = EMPTY_SQUARE
                i += 1
                c -= 1
            end
        else
            pieces[i,j] = Piece(c)
            i += 1
        end

        k += 1
        if i > 8
            j += 1
            i = 1
            @assert board_notation[k] == '/' || (j == 9 && board_notation[k] == ' ')
            k += 1 # skip over '/' or ' '
        end
    end

    white_to_move = board_notation[k] == 'w'
    k += 2
    white_could_castle_kingside = false
    white_could_castle_queenside = false
    black_could_castle_kingside = false
    black_could_castle_queenside = false

    if board_notation[k] == 'K'
        white_could_castle_kingside = true
        k += 1
    end
    if board_notation[k] == 'Q'
        white_could_castle_queenside = true
        k += 1
    end
    if board_notation[k] == 'k'
        black_could_castle_kingside = true
        k += 1
    end
    if board_notation[k] == 'q'
        black_could_castle_queenside = true
        k += 1
    end
    if board_notation[k] == '-'
        k += 1
    end
    k += 1

    en_passant_target_square = Coordinate(0,0)
    reversible_move_count = 0

    return MailboxBoard(pieces,
                        white_to_move,
                        white_could_castle_kingside,
                        white_could_castle_queenside,
                        black_could_castle_kingside,
                        black_could_castle_queenside,
                        en_passant_target_square,
                        reversible_move_count,
                        )
end
@test to_board_notation(MailboxBoard(STARTING_BOARD)) == STARTING_BOARD

const CANVAS_WIDTH = 300
const CANVAS_HEIGHT = CANVAS_WIDTH

const TILE_WIDTH = CANVAS_WIDTH/10 # for 1-tile width margins on each side
const PIECE_RADIUS = TILE_WIDTH*0.3
const PIECE_FONT_SIZE = 15
const LOCATION_RADIUS = TILE_WIDTH*0.45

const COLOR_BACKGROUND = colorant"white"
const COLOR_TILE_LIGHT = colorant"blue"
const COLOR_TILE_DARK = colorant"black"

const COLOR_PIECE_LIGHT = colorant"red"
const COLOR_PIECE_DARK = colorant"green"
const COLOR_HIGHLIGHT = RGBA(1.0,1.0,1.0,0.6)
const COLOR_TEXT = colorant"white"

i2x(i::Integer) = TILE_WIDTH*(i-0.5)

function render_tiles!(rendermodel::RenderModel)
	for i in 1 : 8
	    for j in 1 : 8
	        add_instruction!(rendermodel, render_rect, (VecE2(i2x(i), i2x(j)), TILE_WIDTH, TILE_WIDTH,
	        											mod(i + j, 2) == 1 ? COLOR_TILE_LIGHT : COLOR_TILE_DARK))
	    end
	end

    # render lower labels
    for i in 1 : 8
        add_instruction!(rendermodel, render_text, (string('a' + i - 1), i2x(i), i2x(0), PIECE_FONT_SIZE, colorant"black", true))
    end
    for j in 1 : 8
        add_instruction!(rendermodel, render_text, (string(j), i2x(0), i2x(j), PIECE_FONT_SIZE, colorant"black", true))
    end

	return rendermodel
end
function render_pieces!(rendermodel::RenderModel, pieces::Matrix{Piece})
	for i in 1 : 8
	    for j in 1 : 8
	        piece = pieces[i,j]
	        if piece.char != '_'
	            x = i2x(i)
	            y = i2x(j)
	            add_instruction!(rendermodel, render_circle, (VecE2(x, y), PIECE_RADIUS, piece.white ? COLOR_PIECE_LIGHT : COLOR_PIECE_DARK))
	            add_instruction!(rendermodel, render_text, (string(piece.char), x, y, PIECE_FONT_SIZE, COLOR_TEXT, true))
	        end
	    end
	end
	return rendermodel
end

function render_highlight!(rendermodel::RenderModel, i::Int, j::Int)
	x = i2x(i)
    y = i2x(j)
	add_instruction!(rendermodel, render_circle, (VecE2(x, y), PIECE_RADIUS, COLOR_HIGHLIGHT))
	return rendermodel
end
render_highlight!(rendermodel::RenderModel, pos::Coordinate) = render_highlight!(rendermodel, pos.i, pos.j)
function render_locations!(rendermodel::RenderModel, locations::Vector{Coordinate})
	for loc in locations
		x = i2x(loc.i)
        y = i2x(loc.j)
		add_instruction!(rendermodel, render_circle, (VecE2(x, y), LOCATION_RADIUS, COLOR_HIGHLIGHT))
	end
	return rendermodel
end

function render_board(board::MailboxBoard, locations::Vector{Coordinate}=Coordinate[], highwhiteloc::Coordinate=Coordinate(0,0))
    s = CairoRGBSurface(CANVAS_WIDTH, CANVAS_HEIGHT)
    rendermodel = RenderModel()
    ctx = creategc(s)

    clear_setup!(rendermodel)
    set_background_color!(rendermodel, COLOR_BACKGROUND)
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
ismycolor(board::MailboxBoard, loc::Coordinate, mycolor::Bool) = board.pieces[loc].char != '_' && board.pieces[loc].white == mycolor
isothercolor(board::MailboxBoard, loc::Coordinate, mycolor::Bool) = board.pieces[loc].char != '_' && board.pieces[loc].white != mycolor
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
            dst = shift(loc, dx, dy)
            while inbounds_and_open_or_other_color(board, dst, white)
                push!(coordinates, dst)
                if !isopen(board, dst) && isothercolor(board, dst, white)
                    break
                end
                dst = shift(dst, dx, dy)
            end
		end
	end
	return coordinates
end
function get_pseudo_legal_moves_rook(board::MailboxBoard, loc::Coordinate, white::Bool)
    coordinates = Coordinate[]
	for (dx,dy) in [(-1,0), (0,-1), (1,0), (0,1)]
		dst = shift(loc, dx, dy)
        while inbounds_and_open_or_other_color(board, dst, white)
            push!(coordinates, dst)
            if !isopen(board, dst) && isothercolor(board, dst, white)
                break
            end
            dst = shift(dst, dx, dy)
        end
	end
	return coordinates
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
	    Coordinate(i+0,j+1),
	    Coordinate(i-1,j+1),
	    Coordinate(i-1,j+0),
	    Coordinate(i-1,j-1),
	    Coordinate(i+0,j-1),
	    Coordinate(i+1,j-1),
	    Coordinate(i+1,j+0),
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
        loc_capture = shift(loc, dx, dy)
		if inbounds(loc_capture) && isothercolor(board, loc_capture, white)
			push!(coordinates, loc_capture)
		end
	end

    # TODO: en passant

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
		return Coordinate[]
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
Move(src::Coordinate, dst::Coordinate) = Move(src, dst, '_')

"""
reversible moves increment the clock for use with the fifty-move rule.
All moves by non-pawns to empty target squares.
"""
is_reversible(board::MailboxBoard, move::Move) = board.pieces[move.src].char != 'P' && board.pieces[move.dst].char == '_'

function make_move!(board::MailboxBoard, move::Move)
    if board.pieces[move.src].char == 'P'
        # pawn

        # promotion
        if move.src.j == 1 || move.src.j == 8 # reached the end
            board.pieces[move.dst] = Piece(move.promotion, board.pieces[move.src].white)
            board.pieces[move.src] = EMPTY_SQUARE
        elseif move.dst.i != move.dst.i
            # en passant
            board.pieces[move.dst] = board.pieces[move.src]
            board.pieces[move.src] = EMPTY_SQUARE
            board.pieces[move.src.i, move.dst.j] = EMPTY_SQUARE # capture!
        else
            # normal
            board.pieces[move.dst] = board.pieces[move.src]
            board.pieces[move.src] = EMPTY_SQUARE
        end
    elseif board.pieces[move.src].char == 'K' && abs(move.src.i - move.dst.i) > 1
        # castle
        board.pieces[move.dst] = board.pieces[move.src]
        board.pieces[move.src] = EMPTY_SQUARE

        rook_dst = Coordinate(move.dst.i - div(move.dst.i - move.src.i,2), move.dst.j)
        rook_src = Coordinate(move.dst.i < 4 ? 1 : 8, move.dst.j)
        board.pieces[rook_dst] = board.pieces[rook_src]
        board.pieces[rook_src] = EMPTY_SQUARE
    else
        board.pieces[move.dst] = board.pieces[move.src]
        board.pieces[move.src] = EMPTY_SQUARE
    end

    board.white_to_move = !board.white_to_move
    return board
end
function make_move(board::MailboxBoard, move::Move)
    retval = copy(board) # NOTE: this allocates memory
    make_move!(retval, move)
end

"""
Is the given location within range of a pseudo legal move?
"""
function is_location_in_check(board::MailboxBoard, loc::Coordinate, mycolor::Bool)
    for i in 1 : 8
        for j in 1 : 8
            src = Coordinate(i,j)
            if !ismycolor(board, src, mycolor)
                for dst in get_pseudo_legal_moves(board, src)
                    if dst == loc
                        return true
                    end
                end
            end
        end
    end
    return false
end

function get_king_location(board::MailboxBoard, white::Bool)
    for i in 1 : 8
        for j in 1 : 8
            loc = Coordinate(i,j)
            if board.pieces[loc].char == 'K' && board.pieces[loc].white == white
                return loc
            end
        end
    end
    error("Invalid Codepath")
end

function get_legal_moves(board::MailboxBoard, src::Coordinate)
    @assert ismycolor(board, src, board.white_to_move)
    moves = [Move(src,dst) for dst in get_pseudo_legal_moves(board, src)]
    filter!(move -> begin
                board2 = make_move(board, Move(move))
                my_king_loc = get_king_location(board2, board.white_to_move)
                !is_location_in_check(board2, my_king_loc, board.white_to_move)
            end, moves)
    return moves
end
function get_legal_moves(board::MailboxBoard)
    moves = Move[]
    for i in 1 : 8
        for j in 1 : 8
            src = Coordinate(i,j)
            if ismycolor(board, src, board.white_to_move)
                append!(moves, get_legal_moves(board, src))
            end
        end
    end
    return moves
end

function get_reachable_boards_with_one_more_move(boards::Set{MailboxBoard})
    retval = Set{MailboxBoard}()
    # retval = Vector{MailboxBoard}()
    for board in boards
        for move in get_legal_moves(board)
            push!(retval, make_move(board, move))
        end
    end
    return retval
end
function get_reachable_boards_with_one_more_move(board::MailboxBoard)
    boards = Set{MailboxBoard}()
    # boards = Vector{MailboxBoard}()
    push!(boards, board)
    return get_reachable_boards_with_one_more_move(boards)
end