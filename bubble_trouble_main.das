require dasbox
require graphics
require math
require daslib/decs_boost
require daslib/random
require daslib/defer
require daslib/safe_addr
require daslib/static_let
require daslib/media
require strings
options debugger
require daslib/debug

let
    DEVIL_COLOR = 0xE73847
    WALLS_COLOR = 0x302F2E//0x615F5E
    CEILING_COLOR = 0xC4C3C3
    TIMEBAR_COLOR = 0xDBCB3C
    DEVIL_VEL = 4.0
    DEVIL_MAX_LIVES = 5
    HARPOON_VEL = 800.0
    HARPOON_COLOR = 0x9AB8FA
    HARPOON_STICKY_COLOR = 0xABFDC9
    FLOOR_HEIGHT = 120
    CEILING_HEIGHT = 10
    BONUS_DROP_CHANCE = 30
    BONUS_ADD_TIME = 5.0
    BONUS_ADD_SCORE = 500
    BONUS_TYPE_LIFE = 1
    BONUS_TYPE_HARPOON = 2
    BONUS_TYPE_STICKY_HARPOON = 3
    BONUS_TYPE_TIME = 4
    BONUS_TYPES = 4


struct Level
    num:int
    duration: float
    timeLeft: float
    timeToGetReady: float
    timeToRestart: float
    timeBonus: float
    bgColor: float3
    isFinished: bool
    seed: int4

struct Devil
    pos: float2
    size: float2
    alive: bool
    canFire: bool
    lives: int
    weaponType: int

[decs_template]
struct Ball
    pos: float2
    vel: float2
    radius: float
    color: uint
    nestedBalls: int

[decs_template]
struct Bonus
    pos: float2
    vel: float
    size: float2
    lifetime: float
    color: uint
    bonusType: int

[decs_template]
struct Harpoon
    pos: float2
    vel: float
    length: float
    color: uint

var
    devil: Devil
    level: Level
    score: int


def centered_text(x: int; y:int; text:string; size:int; color:uint)
    set_font_size(size)
    let textSize = get_text_size(text)
    let left = x - int(textSize.x * 0.5)
    text_out(left, y, text, color)

def is_intersect(var rectPos, rectSize, circlePos: float2; circleRadius: float)
    let nearestPtx = clamp(circlePos.x, rectPos.x, rectPos.x + rectSize.x)
    let nearestPty = clamp(circlePos.y, rectPos.y, rectPos.y + rectSize.y)
    let dist = sqrt(pow((nearestPtx - circlePos.x), 2.0) + pow((nearestPty - circlePos.y), 2.0))
    if dist <= circleRadius
        return true
    else
        return false

def segment_point_distance_sq(p0, p1, c:float2)
    let d = p1 - p0
    let l = length_sq(d)
    if (l < 1e-6)
        return length_sq(p0 - c)
    let t = clamp (((c.x - p0.x) * d.x + (c.y - p0.y) * d.y) / l, 0., 1.)
    let nearestPt = t * d + p0
    return length_sq(nearestPt - c)

def random_color(min, max: float)
    var colorRnd: float3
    colorRnd = float3(random_float(level.seed), random_float(level.seed), random_float(level.seed))
    colorRnd = mad(colorRnd, float3(max-min), float3(min))
    return colorRnd

def make_wall(pos, size:float2; isStatic: bool)
    create_entity <| @ (eid, cmp)
        cmp |> set("eid", eid)
        cmp |> set("pos", pos)
        cmp |> set("size", size)
        cmp |> set("color", WALLS_COLOR)
        cmp |> set("obstacle", true)
        cmp |> set("isStatic", isStatic)

def make_ball(pos, vel: float2; radius: float; nestedBalls: int; color: uint)
    create_entity <| @ ( eid, cmp )
        cmp |> set("eid", eid)
        cmp |> set("pos", pos)
        cmp |> set("vel", vel)
        cmp |> set("radius", radius)
        cmp |> set("nestedBalls", nestedBalls)
        cmp |> set("color", color)
        apply_decs_template(cmp, [[Ball pos = pos, vel = vel, radius = radius,
                            nestedBalls = nestedBalls, color = color]])

def make_harpoon(pos: float2; vel: float; len:float; color)
    create_entity <| @ ( eid, cmp )
        cmp |> set("eid", eid)
        cmp |> set("pos", pos)
        cmp |> set("length", len)
        apply_decs_template(cmp, [[Harpoon pos = pos, vel = vel, length = len, color = color]])

def make_bonus(pos: float2; bonusType: int)
    var bonusColor: uint
    if bonusType == BONUS_TYPE_LIFE
        bonusColor = 0xF06B54
    elif bonusType == BONUS_TYPE_HARPOON
        bonusColor = 0x75D847
    elif bonusType == BONUS_TYPE_STICKY_HARPOON
        bonusColor = 0x5478F0
    else
        bonusColor = TIMEBAR_COLOR
    create_entity <| @ ( eid, cmp )
        cmp |> set("eid", eid)
        apply_decs_template(cmp, [[Bonus pos = pos, vel = 200.0, size = float2(15.0, 30.0),
                            lifetime = 5.0, bonusType = bonusType, color = bonusColor]])

def make_devil(var d: Devil)
    d.size = float2(25.0, 50.0)
    d.lives = 3

def make_level()
    let ballsNum = level.num % 2 != 0 ? 1 : 2
    let nestedBalls = int(float(level.num + 1) * 0.5)
    let ballRadius = 5.0 * pow(2.0, float(nestedBalls))
    let ballColor = level.num <= 5 ? 0xDD991B : 0x2DE690
    level.duration += 5.0
    if level.num % 2 == 0
        make_wall(float2(get_screen_width() / 2 - 40, 0), float2(80, get_screen_height() - 250), false)
    for i in range(ballsNum)
        let pos_x = abs((150.0 + ballRadius) - float(i * (get_screen_width())))
        var pos_y = 400.0 - float(level.num) * 25.0 * float(ballsNum) + ballRadius
        if pos_y < 50.0 + ballRadius
            pos_y = 50.0 + ballRadius
        let vel_x = pos_x < float(get_screen_width() / 2) ? 120.0 : -120.0
        make_ball(float2(pos_x, pos_y), float2(vel_x, 0.0), ballRadius, nestedBalls, ballColor)

def reset_scene()
    reset_devil(devil)
    level.timeLeft = 10.0
    level.timeBonus = 0.0
    level.timeToGetReady = 3.0
    level.timeToRestart = 3.0
    reset_time_after_start()
    if level.isFinished
        level.num++
        randomize_seed(level.seed)
        level.bgColor = random_color(0.45, 0.65)
    print("reset_scene\n")
    make_level()
    level.isFinished = false

def level_complete()
    level.isFinished = true
    level.timeToRestart = 3.0

def reset_devil(var d: Devil)
    d.pos = float2(float(get_screen_width()) * 0.5 - d.size.x * 0.5, float(get_screen_height()) - 120.0 - d.size.y)
    d.alive = true
    d.weaponType = 0

def kill_devil(var d: Devil)
    d.alive = false

def move_devil(var d: Devil; vector_x: float)
    if d.alive && level.timeToGetReady <= 0.0 && !level.isFinished
        d.pos.x += vector_x * DEVIL_VEL
        query <| $ [REQUIRE(obstacle)] (eid:EntityId; pos, size: float2)
            let dist = abs(pos.x - d.pos.x)
            if dist < 150.0 && d.pos.y < pos.y + size.y && d.pos.y > pos.y
                if d.pos.x > pos.x
                    let left = pos.x + size.x
                    if d.pos.x < left
                        d.pos.x = left
                else
                    let right = pos.x
                    if d.pos.x > right - d.size.x
                        d.pos.x = right - d.size.x

[decs(stage = update)]
def move_ball(eid:EntityId; var ball: Ball)
    let dt: float = get_delta_time()
    let sh = float(get_screen_height())
    if devil.alive && level.timeToGetReady <= 0.0
        ball.vel.y += dt * 600.0
        ball.pos += dt * ball.vel
        let ballMin = ball.pos - float2(ball.radius)
        let ballMax = ball.pos + float2(ball.radius)
        query <| $ [REQUIRE(obstacle)] (eid:EntityId; pos, size: float2)
            var hadCollision = false
            //temp workaround with an issue when the ball flies right through the floor
            if ball.pos.y > sh - float(FLOOR_HEIGHT) - ball.radius
                ball.pos.y = sh - float(FLOOR_HEIGHT) - ball.radius
                ball.vel.y = -ball.vel.y

            if (!hadCollision && (ballMax.x >= pos.x && ballMax.y >= pos.y &&
            ballMin.x <= pos.x+size.x && ballMin.y <= pos.y+size.y))

                let endPos = pos + size
                let top = segment_point_distance_sq(float2(pos.x, pos.y), float2(endPos.x, pos.y), ball.pos)
                let bottom = segment_point_distance_sq(float2(pos.x, endPos.y), float2(endPos.x, endPos.y), ball.pos)
                let left = segment_point_distance_sq(float2(pos.x, pos.y), float2(pos.x, endPos.y), ball.pos)
                let right = segment_point_distance_sq(float2(endPos.x, pos.y), float2(endPos.x, endPos.y), ball.pos)
                if min(min(top, bottom), min(left, right)) < ball.radius*ball.radius
                    hadCollision = true
                    if min(top, bottom) < ball.radius*ball.radius
                        if (ball.vel.y > 0.) == (top < bottom)
                            ball.vel.y = -ball.vel.y
                if (min(left, right) < ball.radius*ball.radius)
                    if (ball.vel.x > 0.) == (left < right)
                        ball.vel.x = -ball.vel.x


[decs(stage = update)]
def update_ball(eid:EntityId; var ball: Ball)
    var ballKilled: bool = false
    if !devil.alive && level.timeToRestart <= 0.1
        delete_entity(eid)
    if devil.alive && level.timeToGetReady <= 0.0
        if ball.pos.y < float(CEILING_HEIGHT) + ball.radius
            delete_entity(eid)
            score += 100 * (ball.nestedBalls + 1)
            if random_int(level.seed) % 100 < BONUS_DROP_CHANCE
                make_bonus(float2(ball.pos.x, ball.pos.y), (random_int(level.seed) % BONUS_TYPES) + 1)
        query <| $ (eid:EntityId; h:Harpoon)
            if abs(h.pos.x - ball.pos.x) < ball.radius && h.pos.y - h.length <= ball.pos.y + ball.radius
                ballKilled = true
                delete_entity(eid)
        if ballKilled
            delete_entity(eid)
            score += 100 * (ball.nestedBalls + 1)
            if random_int(level.seed) % 100 < BONUS_DROP_CHANCE
                make_bonus(float2(ball.pos.x, ball.pos.y), (random_int(level.seed) % 4) + 1)
            if ball.nestedBalls > 0
                var dir = 1.0
                for i in range(2)
                    make_ball(ball.pos, float2(ball.vel.x * dir, -300.0 - ball.radius * 0.5), ball.radius * 0.5, ball.nestedBalls - 1, ball.color)
                    dir = -1.0
        if is_intersect(devil.pos, devil.size, ball.pos, ball.radius)
            kill_devil(devil)


[decs(stage = update)]
def update_bonus(eid:EntityId; var b: Bonus)
    let dt = get_delta_time()
    let sh = float(get_screen_height())
    let dCenter = devil.pos.x + devil.size.x * 0.5
    let bCenter = b.pos.x + b.size.x * 0.5
    var timeToDeath: float
    if devil.alive
        if b.pos.y < (sh - 120.0 - b.size.y)
            b.pos.y += dt * b.vel
            timeToDeath = get_time_after_start()
        else
            b.pos.y = sh - 120.0 - b.size.y
            b.lifetime -= dt
        if b.lifetime <= 0.0
            delete_entity(eid)
        if b.pos.y > (sh - 120.0 - b.size.y - devil.size.y) && abs(dCenter - bCenter) < (devil.size.x + b.size.x) * 0.5
            if b.bonusType == BONUS_TYPE_LIFE && devil.lives < DEVIL_MAX_LIVES
                devil.lives++
            if b.bonusType == BONUS_TYPE_HARPOON
                devil.weaponType = 1
            if b.bonusType == BONUS_TYPE_STICKY_HARPOON
                devil.weaponType = 0
            if b.bonusType == BONUS_TYPE_TIME
                level.timeBonus += BONUS_ADD_TIME
            score += BONUS_ADD_SCORE
            delete_entity(eid)

[decs(stage = update)]
def kill_bonus(eid:EntityId; var bonus: Bonus)
    if level.timeToRestart <= 0.1
        delete_entity(eid)

[decs(stage = update)]
def level_update(eid: EntityId)
    let ballsExist = find_query <| $ [REQUIRE(nestedBalls)] (pos: float2)
        return true
    if !ballsExist && !level.isFinished && devil.alive
        level_complete()

[decs(stage = update)]
def walls_update(eid: EntityId)
    query <| $ [REQUIRE(obstacle)] (eid:EntityId; pos, size: float2; isStatic:bool)
        if level.timeToRestart <= 0.1 && !isStatic
            delete_entity(eid)

[decs(stage = update)]
def weapon_reload(eid: EntityId)
    let harpoonExist = find_query <| $ [REQUIRE(length)] (pos: float2)
        return true
    if devil.alive && !level.isFinished && !harpoonExist && level.timeToGetReady <= 0.0
        devil.canFire = true
    else
        devil.canFire = false

[decs(stage = update)]
def update_harpoon(eid: EntityId; var h: Harpoon)
    let dt = get_delta_time()
    var hadCollision = false
    if devil.weaponType == 0
        h.color = HARPOON_COLOR
    elif devil.weaponType == 1
        h.color = HARPOON_STICKY_COLOR
    let harpoonTop = float2(h.pos.x, h.pos.y - h.length)
    query <| $ [REQUIRE(obstacle)] (eid:EntityId; pos, size: float2)
        if (!hadCollision && (harpoonTop.x >= pos.x && harpoonTop.y >= pos.y && harpoonTop.x <= pos.x+size.x && harpoonTop.y <= pos.y+size.y))
            if harpoonTop.y <= pos.y + size.y && harpoonTop.y < float(get_screen_height() - FLOOR_HEIGHT)
                hadCollision = true
    if h.pos.y - h.length > float(CEILING_HEIGHT) && !hadCollision
        h.length += dt * h.vel
    elif devil.weaponType == 0
        delete_entity(eid)


def render_devil(var d: Devil)
    let x = int(d.pos.x)
    let y = int(d.pos.y)
    fill_rect(x, y, int(d.size.x), int(d.size.y), DEVIL_COLOR)

[decs(stage = draw)]
def render_walls(var pos, size: float2; color: uint)
    fill_rect(pos.x, pos.y, size.x, size.y, color)

[decs(stage = draw_balls)]
def render_ball(var ball: Ball)
    fill_circle(ball.pos.x, ball.pos.y, ball.radius, ball.color)

[decs(stage = draw_harpoon)]
def render_harpoon(var h: Harpoon)
    var new_pos_y = h.pos.y - h.length
    line(h.pos.x, h.pos.y, h.pos.x, new_pos_y, h.color)

[decs(stage = draw)]
def render_bonus(var bonus: Bonus)
    fill_rect(int(bonus.pos.x), int(bonus.pos.y), int(bonus.size.x), int(bonus.size.y), bonus.color)

def render_timebar()
    if devil.alive && !level.isFinished && level.timeToGetReady <= 0.0
        level.timeLeft = (level.duration - get_time_after_start() + level.timeBonus) / level.duration
    if level.timeLeft > 1.0
        level.timeLeft = 1.0
        level.timeBonus = 0.0
        reset_time_after_start()
    if level.timeLeft <= 0.0
        kill_devil(devil)
    fill_rect(80, get_screen_height() - 100, int(float(get_screen_width() - 80 * 2) * level.timeLeft), 20, TIMEBAR_COLOR)

def render_background()
    var background: Image
    background <- create_image(1, 3, [{uint[] make_color(level.bgColor); make_color(level.bgColor - float3(0.15)); make_color(level.bgColor - float3(0.3))}])
    background |> set_image_smooth(true)
    background |> draw_image(0.0, 0.0, make_color(1.0), float2(get_screen_width(), get_screen_height()))

def render_ceiling()
    var width = get_screen_width()
    for i in range (0, width / 10)
        fill_convex_polygon([[auto float2(float(i) * 10.0 + 0.0, 0.0); float2(float(i) * 10.0 + 10.0, 0.0);
        float2(float(i) * 10.0 + 5.0, float(CEILING_HEIGHT))]], CEILING_COLOR)

def render_score()
    set_font_size(30)
    text_out(get_screen_width() - 300, get_screen_height() - 60, "SCORE: {score}", 0xB6B6B6)

def render_lives()
    for i in range(5)
        fill_rect(80 + 30 * i, get_screen_height() - 60, 15, 30, 0x534242)
    for i in range(devil.lives)
        fill_rect(80 + 30 * i, get_screen_height() - 60, 15, 30, DEVIL_COLOR)

def render_level_num()
    centered_text(get_screen_width() / 2, get_screen_height() - 60, "LEVEL: {level.num}", 30, 0xB6B6B6)

def render_start_title()
    if level.timeToGetReady > 0.0
        fill_rect(0, 0, get_screen_width(), get_screen_height(), make_color(.1, .1, .1, 1.))
        centered_text(get_screen_width() / 2, get_screen_height() / 2 - 70, "GET READY", 100, 0xE7E7E7)

def render_controls()
    if level.num == 1 && level.timeToGetReady > 0.0
        centered_text(get_screen_width() / 2, get_screen_height() / 2 + 50, "MOVEMENT: ARROWS", 20, 0xE7E7E7)
        centered_text(get_screen_width() / 2, get_screen_height() / 2 + 75, "FIRE: SPACE", 20, 0xE7E7E7)

def render_game_over()
    fill_rect(0, 0, get_screen_width(), get_screen_height(), make_color(.1, .1, .1, 1.))
    centered_text(get_screen_width() / 2, get_screen_height() / 2 - 80, "GAME OVER", 80, 0xC09B9B)
    centered_text(get_screen_width() / 2, get_screen_height() / 2 + 20, "PRESS CTRL+F5 TO RESTART", 20, 0xC09B9B)

def render_victory()
    fill_rect(0, 0, get_screen_width(), get_screen_height(), make_color(.1, .1, .1, 1.))
    centered_text(get_screen_width() / 2, get_screen_height() / 2 - 90, "VICTORY", 150, make_color(.7, .9, .7))
    centered_text(get_screen_width() / 2, get_screen_height() - 20, "FEEL FREE TO SEND ANY FEEDBACK TO THE AUTHOR", 10, make_color(.2, .2, .2))

[export]
def initialize
    set_resolution(1280, 720)
    set_antialiasing(4)
    set_window_title("Bubble Trouble")
    randomize_seed(level.seed)
    level.num = 1
    level.duration = 20.0
    score = 0
    level.bgColor = random_color(0.45, 0.65)
    make_devil(devil)
    reset_scene()
    level.timeToGetReady = 5.0
    make_wall(float2(0, get_screen_height() - FLOOR_HEIGHT), float2(get_screen_width(), FLOOR_HEIGHT), true) //ground
    make_wall(float2(0, 0), float2(80, get_screen_height()), true)
    make_wall(float2(get_screen_width() - 80, 0), float2(80, get_screen_height()), true)


[export]
def act(dt: float)
    if get_key(VK_ESCAPE)
        schedule_quit_game()
    if get_key(VK_LEFT) || get_key(VK_A)
        move_devil(devil, -1.0)
    if get_key(VK_RIGHT) || get_key(VK_D)
        move_devil(devil, 1.0)
    if get_key(VK_SPACE) && devil.canFire
        var harpoonColor = HARPOON_COLOR
        if devil.weaponType == 0
            harpoonColor = HARPOON_STICKY_COLOR
        make_harpoon(float2(devil.pos.x + devil.size.x * 0.5, float(get_screen_height() - FLOOR_HEIGHT)), HARPOON_VEL, 0.0, harpoonColor)

    if level.timeToGetReady > 0.0
        level.timeToGetReady -= dt
        reset_time_after_start()

    if level.timeToRestart > 0.0
        if !devil.alive || level.isFinished
            level.timeToRestart -= dt
    else
        if !devil.alive && devil.lives > 0
            devil.lives--
            reset_scene()
        if level.isFinished
            reset_scene()

    decs_stage("update")


[export]
def draw()
    render_background()
    render_ceiling()
    decs_stage("draw_balls")
    decs_stage("draw_harpoon")
    decs_stage("draw")
    render_devil(devil)
    render_score()
    render_lives()
    render_level_num()
    render_timebar()
    render_start_title()
    render_controls()
    if devil.lives == 0
        render_game_over()
    if level.num == 11
        render_victory()