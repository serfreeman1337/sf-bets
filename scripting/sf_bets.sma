/*
*	SF Bets				     v. 0.1
*	by serfreeman1337	http://gf.hldm.org/
*/

#include <amxmodx>
#include <cstrike>
#include <hamsandwich>

#define PLUGIN "SF Bets"
#define VERSION "0.1"
#define AUTHOR "serfreeman1337"

//#define AES	// расскоментируйте для возможности ставить опыт AES (http://1337.uz/advanced-experience-system/)

#if defined AES
	#include <aes_main>
#endif

#if AMXX_VERSION_NUM < 183
	#include <colorchat>
	
	#define print_team_default DontChange
	#define print_team_grey Grey
	#define print_team_red Red
	#define print_team_blue Blue

	#define MAX_PLAYERS 32
	#define MAX_NAME_LENGTH 32
	
	#define argbreak strbreak
#endif

// данный код не рекомендуется смотреть людям страдающим синдромом оптимизации

// -- КОНСТАНТЫ -- //

enum _:players_data_struct
{
	BET_FOR,		// на кого поставил игрок
	BET_MONEY		// деньги
	
	#if defined AES
	,BET_EXP,
	BET_BONUS
	#endif
}

enum _:cvars
{
	CVAR_MIN_PLAYERS,
	CVAR_BET_TIME,
	CVAR_BET_AUTOOPEN,
	CVAR_BET_MONEY
	
	#if defined AES
	,CVAR_BET_EXP,
	CVAR_BET_BONUS
	#endif
}

const taskid_updatemenu		= 31337

// -- ПЕРЕМЕННЫЕ -- //

new t_id,ct_id			// id игроков 1х1
new Float:bet_time			// время ставки
new bet_menu
new max_players			// храним количество игроков

new players_data[MAX_PLAYERS + 1][players_data_struct]

new cvar[cvars]

new HamHook:hook_playerKilled
new menuCB_bet

public plugin_init()
{
	register_plugin(PLUGIN,VERSION,AUTHOR)
	
	hook_playerKilled = RegisterHam(Ham_Killed,"player","HamHook_PlayerKilled",true)
	register_logevent("Bet_CheckMinPlayers",3,"1=joined team")
	register_event("SendAudio", "EventHook_TWin", "a", "2&%!MRAD_terwin")  
	register_event("SendAudio", "EventHook_CtWin", "a", "2&%!MRAD_ctwin") 
	register_event("HLTV", "EventHook_NewRound", "a", "1=0", "2=0")
	
	//
	// Минимальное количество игроков в обеих командах для работы ставок
	//
	cvar[CVAR_MIN_PLAYERS] = register_cvar("sf_bet_min_players","2")
	
	//
	// Время, в течении которого можно сделать ставку
	//
	cvar[CVAR_BET_TIME] = register_cvar("sf_bet_time","8")
	
	//
	// Ставка денег
	//
	cvar[CVAR_BET_MONEY] = register_cvar("sf_bet_money","100 1000 3000")
	
	#if defined AES
	//
	// Ставка опыта
	//
	cvar[CVAR_BET_EXP] = register_cvar("sf_bet_exp","")
	
	//
	// Ставка бонусов
	//
	cvar[CVAR_BET_BONUS] = register_cvar("sf_bet_bonus","")
	#endif
	
	//
	// Автоматическое открытие меню ставок
	//
	cvar[CVAR_BET_AUTOOPEN] = register_cvar("sf_bet_auto","1")
	
	register_clcmd("say /bet","Bet_ShowMenu",-1,"- open bet menu")
	
	register_dictionary("sf_bets.txt")
	register_dictionary("common.txt")
	max_players = get_maxplayers()
}

public plugin_cfg()
{
	server_exec()
	
	// --- МЕНЮ --- //
	
	bet_menu = menu_create("Bet Menu","Bet_MenuHandler")
	menuCB_bet = menu_makecallback("Bet_MenuCallback")
	
	menu_additem(bet_menu,"Player T","0",.callback = menuCB_bet)
	menu_additem(bet_menu,"Player CT","1",.callback = menuCB_bet)
	
	new v_cvar[10]
	get_pcvar_string(cvar[CVAR_BET_MONEY],v_cvar,charsmax(v_cvar))
	
	if(v_cvar[0])
		menu_additem(bet_menu,"Money","2",.callback = menuCB_bet)
	
	#if defined AES
	get_pcvar_string(cvar[CVAR_BET_EXP],v_cvar,charsmax(v_cvar))
	
	if(v_cvar[0])
		menu_additem(bet_menu,"Exp","3",.callback = menuCB_bet)
		
	get_pcvar_string(cvar[CVAR_BET_BONUS],v_cvar,charsmax(v_cvar))
	
	if(v_cvar[0])
		menu_additem(bet_menu,"Bonus","4",.callback = menuCB_bet)
	#endif
}


public client_disconnect(id)
{
	// TODO: придумать что-то
	set_task(0.1,"Bet_CheckMinPlayers")
	
	arrayset(players_data[id],0,players_data_struct)
}

//
// Победа T
//
public EventHook_TWin()
{
	if(t_id && ct_id)
		Bet_End1x1(t_id)
}

//
// Победа CT
//
public EventHook_CtWin()
{
	if(t_id && ct_id)
		Bet_End1x1(ct_id)
}

public EventHook_NewRound()
{
	if(t_id || ct_id)
	{
		for(new i; i < max_players ; i++)
		{
			arrayset(players_data[players[i]],0,players_data_struct)
		}
		
		t_id = 0
		ct_id = 0
		bet_time = 0.0
	}
}

//
// Вкл/выкл обнаружения 1x1 по кол-ву игроков в командах
//
public Bet_CheckMinPlayers()
{
	new players[MAX_PLAYERS],pnum,min_players = get_pcvar_num(cvar[CVAR_MIN_PLAYERS])
	
	// проверяем кол-во игроков за T
	get_players(players,pnum,"e","TERRORIST")
	
	if(pnum < min_players)
	{
		DisableHamForward(hook_playerKilled)
		return PLUGIN_CONTINUE
	}
	
	// проверяем кол-во игроков за CT
	get_players(players,pnum,"e","CT")
	
	if(pnum < min_players)
	{
		DisableHamForward(hook_playerKilled)
		return PLUGIN_CONTINUE
	}
	
	// вкл все
	
	if(Bet_Check1x1())
	{
		Bet_Start()
	}
	
	EnableHamForward(hook_playerKilled)
	return PLUGIN_CONTINUE
}

public HamHook_PlayerKilled()
{
	if(Bet_Check1x1())
	{
		Bet_Start()
	}
}

//
// Начало 1х1
//
public Bet_Start()
{
	bet_time = get_gametime() + get_pcvar_float(cvar[CVAR_BET_TIME])
	
	// показываем меню всем
	if(get_pcvar_num(cvar[CVAR_BET_AUTOOPEN]))
	{
		new players[MAX_PLAYERS],pnum
		get_players(players,pnum,"ch")
		
		for(new i,player ; i < pnum ; i++)
		{
			player = players[i]
			
			Bet_ShowMenu(player)
		}
	}
	
	// таск обновление меню игрокам
	if(!task_exists(taskid_updatemenu))
		set_task(0.5,"Bet_UpdateMenu",taskid_updatemenu,.flags = "b")
}

//
// Конец 1x1
//
public Bet_End1x1(win_practicant)
{
	new players[MAX_PLAYERS],pnum
	get_players(players,pnum,"ch")
	
	bet_time = 0.0
	remove_task(taskid_updatemenu)
	Bet_UpdateMenu()
	
	for(new i,player ; i < pnum ; i++)
	{
		player = players[i]
		
		// игрок не делал ставку
		if(!players_data[player][BET_FOR])
		{	
			continue
		}
		
		// победная ставка
		if(players_data[player][BET_FOR] == win_practicant)
		{
			new win_name[MAX_NAME_LENGTH]
			get_user_name(players_data[player][BET_FOR],win_name,charsmax(win_name))
			
			new prize,prize_str[128],prize_len
			
			prize = Bet_GetWinPool(player,BET_MONEY,win_practicant)
			
			// выдаем деньги
			if(prize)
			{
				prize_len += formatex(prize_str[prize_len],charsmax(prize_str) - prize_len,"%L",
					player,"SF_BET14",
					prize
				)
				
				cs_set_user_money(player,
					cs_get_user_money(player) + prize
				)
			}
			
			#if defined AES
			// выдаем опыт
			prize = Bet_GetWinPool(player,BET_EXP,win_practicant)
			
			if(prize)
			{
				prize_len += formatex(prize_str[prize_len],charsmax(prize_str) - prize_len,"%s%L",
					prize_len ? ", " : "",
					player,"SF_BET15",
					prize
				)
				
				aes_add_player_exp(player,prize)
			}
			
			// выдаем бонусы
			prize = Bet_GetWinPool(player,BET_BONUS,win_practicant)
			
			if(prize)
			{
				prize_len += formatex(prize_str[prize_len],charsmax(prize_str) - prize_len,"%s%L",
					prize_len ? ", " : "",
					player,"SF_BET21",
					prize
				)
				
				aes_add_player_bonus(player,prize)
			}
			#endif
			
			client_print_color(player,print_team_blue,"%L %L",
				player,"SF_BET9",
				player,"SF_BET13",
				win_name,prize_str
			)
		}
		// фейловая ставка
		else
		{
			new lose_name[MAX_NAME_LENGTH]
			get_user_name(players_data[player][BET_FOR],lose_name,charsmax(lose_name))
			
			client_print_color(player,print_team_red,"%L %L",
				player,"SF_BET9",
				player,"SF_BET12",
				lose_name
			)
		}
		
		arrayset(players_data[player],0,players_data_struct)
	}
}

//
// Функция обновления меню игрокам
//
public Bet_UpdateMenu()
{
	new players[MAX_PLAYERS],pnum
	get_players(players,pnum,"ch")
	
	new Float:bet_left = bet_time - get_gametime()
	
	for(new i,player,menu,newmenu,menupage ; i < pnum ; i++)
	{
		player = players[i]
		
		player_menu_info(player,menu,newmenu,menupage)
		
		// обновляем меню ставок игроку
		if(newmenu == bet_menu)
		{
			// обновляем меню
			if(floatround(bet_left) > 0)
			{
				menu_display(player,bet_menu)
			}
			// закрываем меню по истечению времени
			else
			{
				menu_cancel(player)
				show_menu(player,0,"^n")
			}
		}
	}
	
	// сбрасываем такс
	if(bet_left <= 0.0)
	{
		remove_task(taskid_updatemenu)
	}
}

//
// Показываем меню ставок
//
public Bet_ShowMenu(id)
{
	// hax
	if(id == t_id || id == ct_id)
	{
		return PLUGIN_HANDLED
	}
	
	// меню можно вызвать только 1x1
	if(!t_id || !ct_id)
	{
		client_print_color(id,print_team_red,"%L %L",
			id,"SF_BET9",
			id,"SF_BET10"
		)
		
		return PLUGIN_CONTINUE
	}
	
	if(players_data[id][BET_FOR])
	{
		client_print_color(id,print_team_red,"%L %L",
			id,"SF_BET9",
			id,"SF_BET18"
		)
		
		return PLUGIN_CONTINUE
	}
	
	// меню можно вызвать только живым
	if(is_user_alive(id))
	{
		client_print_color(id,print_team_red,"%L %L",
			id,"SF_BET9",
			id,"SF_BET11"
		)
		
		return PLUGIN_CONTINUE
	}
	
	new Float:bet_left = bet_time - get_gametime()
	
	if(bet_left <= 0.0)
	{
		client_print_color(id,print_team_red,"%L %L",
			id,"SF_BET9",
			id,"SF_BET17"
		)
		
		return PLUGIN_CONTINUE
	}
	
	Bet_MenuFormat(id)
	menu_display(id,bet_menu)
	
	return PLUGIN_CONTINUE
	
}

//
// Обработка действий в меню
//
public Bet_MenuHandler(id,menu,r_item)
{
	if(r_item == MENU_EXIT)
	{
		return PLUGIN_HANDLED
	}
	
	new ri[2],di[2]
	menu_item_getinfo(menu,r_item,di[0],ri,charsmax(ri),di,charsmax(di),di[0])
	
	new item = str_to_num(ri)
	
	switch(item)
	{
		// делаем ставки
		case 0,1:
		{	
			// ставим деньги
			if(players_data[id][BET_MONEY])
			{
				new user_money = cs_get_user_money(id)
				
				// игроку не хватает денег
				if(user_money < players_data[id][BET_MONEY])
				{
					menu_display(id,menu)
					
					return PLUGIN_HANDLED
				}
				
				// списываем деньги
				cs_set_user_money(id,
					cs_get_user_money(id) - players_data[id][BET_MONEY]
				)
			}
			
			#if defined AES
			new rt[AES_ST_END]
			aes_get_player_stats(id,rt)
			
			// ставим опыт
			if(players_data[id][BET_EXP])
			{
				if(rt[AES_ST_EXP] < players_data[id][BET_EXP])
				{
					menu_display(id,menu)
					
					return PLUGIN_HANDLED
				}
				
				aes_add_player_exp(id,-players_data[id][BET_EXP])
			}
			
			if(players_data[id][BET_BONUS])
			{
				if(rt[AES_ST_BONUSES] < players_data[id][BET_BONUS])
				{
					menu_display(id,menu)
					
					return PLUGIN_HANDLED
				}
				
				aes_add_player_bonus(id,-players_data[id][BET_BONUS])
			}
			
			// ставим бонусы
			#endif
			
			// запоминаем на кого поставили
			players_data[id][BET_FOR] = item == 0 ? t_id : ct_id
		}
		// переключатели стаовк
		case 2,3,4:
		{
			new cp = CVAR_BET_MONEY + (item - 2)
			new sp = BET_MONEY + (item - 2)
			
			new bet_str[128],bet_val[10],bool:set
			get_pcvar_string(cvar[cp],bet_str,charsmax(bet_str))
			
			while(argbreak(bet_str,
				bet_val,charsmax(bet_val),
				bet_str,charsmax(bet_str)) != -1
			)
			{
				if(!bet_val[0])
					break
				
				bet_val[0] = str_to_num(bet_val)
				
				// переключаем на большее значение
				if(bet_val[0] > players_data[id][sp])
				{
					set = true
					players_data[id][sp] = bet_val[0]
					break
				}
			}
			
			// сбрасываем переключатель
			if(bet_val[0] <= players_data[id][sp] && !set)
			{
				players_data[id][sp] = 0
			}
			
			switch(item)
			{
				case 2:
				{
					if(cs_get_user_money(id) < players_data[id][sp])
					{
						players_data[id][sp] = 0
					}
				}
				#if defined AES
				case 3,4:
				{
					new rt[AES_ST_END]
					aes_get_player_stats(id,rt)
					
					if(
						(item == 3 && rt[AES_ST_EXP] < players_data[id][sp])
						||
						(item == 4 && rt[AES_ST_BONUSES] < players_data[id][sp])
					)
					{
						players_data[id][sp] = 0
					}
				}
				#endif
			}
			
			menu_display(id,menu)
		}
	}
	
	return PLUGIN_HANDLED
}


//
// Настраиваем отображение меню
//
public Bet_MenuFormat(id)
{
	new fmt[512],len
	
	// --- ЗАГОЛОВОК --- //
	len += formatex(fmt[len],charsmax(fmt) - len,"%L^n%L^n%L",
		id,"SF_BET1",
		id,"SF_BET2",bet_time - get_gametime(),
		id,"SF_BET3",Bet_Menu_GetBetString(id)
	)
	menu_setprop(bet_menu,MPROP_TITLE,fmt)
	
	// --- ВЫХОД --- //
	formatex(fmt,charsmax(fmt),"%L",id,"EXIT")
	menu_setprop(bet_menu,MPROP_EXITNAME,fmt)
}

//
// Настраиваем кнопки в меню
//
public Bet_MenuCallback(id, menu, r_item)
{
	new fmt[256],len
	
	new ri[2],di[2]
	menu_item_getinfo(menu,r_item,di[0],ri,charsmax(ri),di,charsmax(di),di[0])
	
	new item = str_to_num(ri)
	
	if(item == 0)
	{
		Bet_MenuFormat(id)
	}
	
	switch(item)
	{
		// ставка на T
		case 0:
		{
			new t_name[MAX_NAME_LENGTH]
			get_user_name(t_id,t_name,charsmax(t_name))
			
			len = formatex(fmt[len],charsmax(fmt) - len,"%L",
				id,"SF_BET6",
				t_name,
				"T"
			)
			
			new prize = Bet_GetWinPool(id,BET_MONEY,t_id)
			new prize_str[128],prize_len
			
			if(prize)
			{
				prize_len += formatex(prize_str[prize_len],charsmax(prize_str) - prize_len,"%L",
					id,"SF_BET5",
					prize
				)	
			}
			
			#if defined AES
			prize = Bet_GetWinPool(id,BET_EXP,t_id)
			
			if(prize)
			{
				prize_len += formatex(prize_str[prize_len],charsmax(prize_str) - prize_len,"%s%L",
					prize_len ? ", " : "",
					id,"SF_BET4",
					prize
				)
			}
			
			prize = Bet_GetWinPool(id,BET_BONUS,t_id)
			
			if(prize)
			{
				prize_len += formatex(prize_str[prize_len],charsmax(prize_str) - prize_len,"%s%L",
					prize_len ? ", " : "",
					id,"SF_BET20",
					prize
				)
			}
			#endif
			
			if(prize_str[0])
			{
				len += formatex(fmt[len],charsmax(fmt) - len," %L",
					id,"SF_BET16",
					prize_str
				)
			}
			
			menu_item_setname(menu,r_item,fmt)
			
			#if defined AES
			if(!players_data[id][BET_MONEY] && !players_data[id][BET_EXP])
				return ITEM_DISABLED
			#else
			if(!players_data[id][BET_MONEY])
				return ITEM_DISABLED
			#endif
		}
		// ставка на CT
		case 1:
		{
			new ct_name[MAX_NAME_LENGTH]
			get_user_name(ct_id,ct_name,charsmax(ct_name))
	
			len = formatex(fmt[len],charsmax(fmt) - len,"%L",
				id,"SF_BET6",
				ct_name,
				"CT"
			)
			
			new prize = Bet_GetWinPool(id,BET_MONEY,ct_id)
			new prize_str[128],prize_len
			
			if(prize)
			{
				prize_len += formatex(prize_str[prize_len],charsmax(prize_str) - prize_len,"%L",
					id,"SF_BET5",
					prize
				)	
			}
			
			#if defined AES
			prize = Bet_GetWinPool(id,BET_EXP,t_id)
			
			if(prize)
			{
				prize_len += formatex(prize_str[prize_len],charsmax(prize_str) - prize_len,"%s%L",
					prize_len ? ", " : "",
					id,"SF_BET4",
					prize
				)
			}
			
			prize = Bet_GetWinPool(id,BET_BONUS,t_id)
			
			if(prize)
			{
				prize_len += formatex(prize_str[prize_len],charsmax(prize_str) - prize_len,"%s%L",
					prize_len ? ", " : "",
					id,"SF_BET20",
					prize
				)
			}
			#endif
			
			if(prize_str[0])
			{
				len += formatex(fmt[len],charsmax(fmt) - len," %L",
					id,"SF_BET16",
					prize_str
				)
			}
			
			len += formatex(fmt[len],charsmax(fmt) - len,"^n")
			
			menu_item_setname(menu,r_item,fmt)
			
			#if defined AES
			if(!players_data[id][BET_MONEY] && !players_data[id][BET_EXP])
				return ITEM_DISABLED
			#else
			if(!players_data[id][BET_MONEY])
				return ITEM_DISABLED
			#endif
		}
		// переключатели
		case 2,3,4:
		{
			new cp = CVAR_BET_MONEY + (item - 2)
			new sp = BET_MONEY + (item - 2)
			
			switch(item)
			{
				case 2: len = formatex(fmt[len],charsmax(fmt) - len,"%L",id,"SF_BET7")
				
				#if defined AES
				case 3: len = formatex(fmt[len],charsmax(fmt) - len,"%L",id,"SF_BET8")
				case 4: len = formatex(fmt[len],charsmax(fmt) - len,"%L",id,"SF_BET19")
				#endif
			}
			
			new bet_str[128],bet_val[10]
			get_pcvar_string(cvar[cp],bet_str,charsmax(bet_str))
			
			if(!bet_str[0])
			{
				menu_item_setname(bet_menu,r_item,fmt)
				return ITEM_DISABLED
			}
			
			while(argbreak(bet_str,
				bet_val,charsmax(bet_val),
				bet_str,charsmax(bet_str)) != -1
			)
			{
				if(!bet_val[0])
					break
				
				bet_val[0] = str_to_num(bet_val)
				
				if(bet_val[0] != players_data[id][sp])
				{
					len += formatex(fmt[len],charsmax(fmt) - len," \d[%d]",bet_val[0])
				}
				else
				{
					len += formatex(fmt[len],charsmax(fmt) - len," \r[\y%d\r]",bet_val[0])
				}
			}
			
			menu_item_setname(bet_menu,r_item,fmt)
		}
	}
	
	return ITEM_ENABLED
}

//
// лул
//
Bet_Menu_GetBetString(id)
{
	new fmt[512],len
	
	if(players_data[id][BET_MONEY])
	{
		len += formatex(fmt[len],charsmax(fmt) - len,"%L",id,"SF_BET5",
			players_data[id][BET_MONEY]
		)
	}
	
	#if defined AES
	if(players_data[id][BET_EXP])
	{
		len += formatex(fmt[len],charsmax(fmt) - len,"%s%L",fmt[0] ? ", " : "",id,"SF_BET4",
			players_data[id][BET_EXP]
		)
	}
	
	if(players_data[id][BET_BONUS])
	{
		len += formatex(fmt[len],charsmax(fmt) - len,"%s%L",fmt[0] ? ", " : "",id,"SF_BET20",
			players_data[id][BET_BONUS]
		)
	}
	#endif
	
	if(!fmt[0])
	{
		copy(fmt,charsmax(fmt),"\d-\w")
	}
	
	return fmt
}

//
// Узнаем выигрыш ставки
//
Bet_GetWinPool(id,pool,practicant)
{
	new players[MAX_PLAYERS],pnum
	get_players(players,pnum,"ch")
	
	new bet_pool
	
	for(new i,player ; i <pnum ; i++)
	{
		player = players[i]
		
		if(players_data[player][BET_FOR] != 0 && players_data[player][BET_FOR] != practicant)
		{
			continue
		}
		
		bet_pool += players_data[player][pool]
	}
	
	if(!bet_pool)
		return 0
	
	// процент ставки игрока от общей суммы
	new Float:bet_perc = float(players_data[id][pool]) * 100.0 / float(bet_pool)
	
	return bet_pool * floatround(bet_perc) / 100
}

//
// Функция проверки 1x1
//
Bet_Check1x1()
{
	if(t_id && ct_id)
		return false
	
	new players[MAX_PLAYERS],tnum,ctnum
	
	// живые игрока из T
	get_players(players,tnum,"aeh","TERRORIST")
	
	if(tnum == 1)
	{
		// запоминаем ID посл. живого T
		t_id  = players[0]
	}
	else
	{
		t_id = 0
		
		return false
	}
	
	// живые игроки за CT
	get_players(players,ctnum,"aeh","CT")
	
	if(ctnum == 1)
	{
		// запоминаем ID посл. живого CT
		ct_id = players[0]
	}
	else
	{
		ct_id = 0
		
		return false
	}
	
	// это 1x1
	return true
}
