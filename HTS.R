## загрузка нужных библиотек
# для парсинга XML и/или JSON - vk возвращает данные в таких форматах
library(XML)
library(rjson)
# и для работы с данными, напр. поддержкой data frames
library(plyr)

# команды для каталогов
setwd("~/Dropbox/evfr/HTS/")
load('.RData')

## поисковые параметры
# ---------------- #
# минимальный и максимальный возраст
minAge <- 21
maxAge <- 25
# пол
sex <- 'F'
# срок последней активности в днях
activity <- 20
# идеология - поле анкеты пользователей religion
ideology <- c('трансгуманизм', 'иммортализм')
# корни Т-слов для grep'анья
Twords <- c('трансгуман', 'иммортали', 'крион', 'бессмерт', 'нанотехн', 'сингулярн', 'геронтол', 'киборг', 'апгрейд')
# ---------------- #

## чтение списка целевых групп - табулированный файл со списком групп и категорий групп
groupsDB <- read.table('db/groupsDB.tab', header = T, stringsAsFactors = F)
## чтение чёрного списка - табулированныцй файл с ID юзеров
blacklist <- read.table('data/BlackList.tab', header = T, stringsAsFactors = F)


## скачивание полных списков участников всех целевых групп
# получить список имён групп для цикла
targets <- groupsDB$group
# обход циклом процедуры скачки для каждой группы
for (target in targets) {
	# диагностический вывод имени
  print(paste('  Group:  ', target))
	# пауза перед запросом чтобы не забанили на vk
  Sys.sleep(0.5)
	# запрос информации о группе к API vk по методу groups.getById с возвращаемым полем members_count с сохранением ответа во временный файл /tmp/<target>.txt
  download.file(paste0('https://api.vk.com/method/groups.getById?group_id=', target, '&fields=members_count'), destfile=paste0('/tmp/', target, '.txt'), method='wget', quiet = T)
	# составление переменной имени файла
  tmp_file <- paste0('/tmp/',target, '.txt')
	# парсинг JSON файла
  tmp <- fromJSON(file = tmp_file)
	# вытаскивание из JSON файла целевого значения числа пользователей из поля members_count
  member_count <- tmp$response[[1]]$members_count
	# вывод числа пользователей
  print(paste('    members  ', member_count))
	# удаление временного файла
  system(paste0('rm /tmp/', target, '.txt'))
	# вычисление числа шагов блочного скачивания всех членов группы (vk возвращает только по 1000 участников группы за возвращение) как округление к меньшему member_count / 1000
  stepSize <- as.integer(member_count / 1000)
	# пробег цикла по последовательности 0 .. <число шагов>
  for (s in seq(0, stepSize)) {
		# пауза чтобы не банили
    Sys.sleep(0.5)
		# запрос информации о группе к API vk по методу groups.getMembers с отступом вывода пользователей <номер_шага> x 1000 при выводе полей информации пользователей sex, bdate, city, country, last_seen, relation с сохранением во временный файл '/tmp/vkDB-<номер_шага>-<target>.txt' и приделанным в запрос токеном для доступа к информации пользователей к отключённым доступом у незареганных в vk
    download.file(paste0('https://api.vk.com/method/groups.getMembers?group_id=', target, '&offset=', s * 1000,'&fields=sex,bdate,city,country,last_seen,relation&access_token=', token), destfile = paste0('/tmp/vkDB-', s, '-', target, '.txt'), method = 'wget', quiet = T)
  }
}


## парсинг скачанных блочных полных списков участников целевых групп
# инициализация словаря-контейнера данных
usersdata <- list()
# пробегание цикла по всем целевым группам
for (target in targets) {
	# инициализация элемента списка для конкретной группы <target> как хранилища данных типа data frame
  usersdata[[target]] <- data.frame()
	# диагностический вывод "парсится данные группы такой-то"
  print(paste('parsing group:', target))
	# пробегание по всем файлам с блоками данных для группы <target>
  for (filename in list.files('/tmp/', pattern = paste0('*-', target, '.txt'))) {
		# формирование переменной с путем к файлу
    tmp_file <- paste0('/tmp/', filename)
		# парсинг JSON файла
    tmp <- fromJSON(file = tmp_file)
		# конвертация JSON данных в данные табличного формата data frame
    tmpdata <- do.call("rbind.fill", lapply(tmp$response$users, function(x) as.data.frame(x, stringsAsFactors = F)))
		# проверка пустой-ли элемент списка конкретноый группы или нет
    if (nrow(usersdata[[target]]) == 0) {
			# если пустой - наполнить его сконвертированными из JSON в data frame данными
      usersdata[[target]] <- tmpdata
    } else {
			# если не пустой - объединить (склеить по строкам и объединить наборы имён столбцов) имеющиеся там данные и полученными из JSON в data frame данными
      usersdata[[target]] <- merge(usersdata[[target]], tmpdata, all = T)
    }
		# стереть из памяти данные, хз зачем прописано, иногда были глюки
    rm(tmpdata)
  }
}


## слияние данных в единую структуру данных data frame табличного типа vkdata
# инициализировать data frame для этого
vkdata <- data.frame()
# пробегание по циклу всех групп по их именам
for (target in targets) {
	# формирование строкового массива из имени <target> длиной, равной member_count для группы <target>
  category <- as.vector(rep(target, nrow(usersdata[[target]])))
	# проверить на нулевое число рядов vkdata
  if (nrow(vkdata) == 0) {
		# если 0, но присвоить ей "значение" в виде таблицы пользователей группы <target> с приклееным столбцом с повторяющимся именем группы (чтобы не было одинаковых строк в таблице в случае одних и тех-же пользователей из разных групп, последний столбец будет в случае дубликатов иметь разные имена <target>)
    vkdata <- cbind(usersdata[[target]], category)
  } else {
		# если не 0 - приклеить новые строки 
    vkdata <- rbind(vkdata, cbind(usersdata[[target]], category))
  }
	# удалить из памяти массив имён группы
  rm(category)
}
# удалить из памяти список с таблицами данных для каждой группы в отдельности
rm(usersdata)


## преобразование объединённой таблицы vkdata в таблицу с единожны встречающейся строкой о каждом пользователе и статистикой и принадлежности каждого пользователя к группам всех категорий
# определение числа колонок таблицы vkdata
sizeTab <- ncol(vkdata)
# подготовка таблицы выборки с числом колонок на 1 меньшим, чем в vkdata
selected <- data.frame(matrix(0, ncol = sizeTab - 1))
# копирование имён колонок для таблицы selected из имён колонок vkdata с исключением последней колонки category (с повторами имён групп)
colnames(selected) <- colnames(vkdata[,1:(sizeTab - 1)])
# получить список ID vk из таблицы vkdata без повторений
uids <- unique(vkdata$uid)
# инициализировать data frame с нулями (бланк для заполнения численными параметрами) с числом строк, равным числу пользователей в таблице без повторений и числом столбцов, равным числу категорий групп
template <- as.data.frame(matrix(0, ncol = length(unique(groupsDB$category)), nrow = length(unique(vkdata$uid))))
# назвать колонки этого бланка именами категорий групп
colnames(template) <- unique(groupsDB$category)
# пробегание цикла по номерам всех элементов списка ID пользователей без повторений
for (n in 1:length(uids)) {
	# получить сам идентификатор uid по его номеру в списке
  uid <- uids[n]
	# сохранить во временную таблицу все строки с данными пользователя из vkdata с идентификатором uid - от 1 строки до стольки строк, в скольки разных целевых группах состоит пользователь
  tmp <- vkdata[vkdata$uid == uid,]
	# сохранить в таблицу выборки одну (или единственную) строку из временной таблицы с отсечением последнего столбца в именем группы
  selected[n,] <- tmp[1, 1:(sizeTab - 1)]
  
	# получить строковый вектор из категорий тех групп, имена которых есть в последнем столбце временной таблицы,
	# вычислить статистику "сколько раз встречается группа каждой категории",
	# преобразовать в числовой вектор с именами
  tmp <- t(as.matrix(table(groupsDB[tmp$category, 'category'])))
	# сохранить числа полученного вектора в строку бланка template для пользователя под номером n в списке идентификаторов с учётом имён элементов вектора как имён столбцов бланка
  template[n,colnames(tmp)] <- as.vector(tmp)
}
# склеить столбцы таблицы данных пользователей selected и заполненного числами встречаемости бланка template
selected <- cbind(selected, template)
# удалить из памяти неповторяющийся список пользователей и бланк
rm(uids, template)


### ### Фильтрация
# удалить бесполезную колонку last_seen.platform
selected <- selected[,!(colnames(selected) %in% c('last_seen.platform'))]

## первичная фильтрация
# задание соответствия полу M/F цифрового кода vk
gender <- c(0, 1)
names(gender) <- c('M', 'F')
# оставить только нужный пол
selected <- selected[selected$sex == gender[[sex]],]
# убрать ненужную уже колонку про пол
selected <- selected[,!colnames(selected) == 'sex']
# выбрать не забаненных и не заблокированных, оставив тех, у кого колонка deactivated содержит NA
selected <- selected[is.na(selected$deactivated),]
# удалить колонку 'deactivated'
selected <- selected[,!colnames(selected) == 'deactivated']

# выбрать "single", "actively searching" и "it's complicated"* по статусу отношений
# 1 – single
# 2 – in a relationship
# 3 – engaged
# 4 – married
# 5 – it's complicated
# 6 – actively searching
# 7 – in love
# удалить типы отношений со значениями 2, 3, 4 и 7
selected <- selected[!selected$relation %in% c(2,3,4,7),]
# удалить тех, у кого есть партнёр, с кем всё сложно
selected <- selected[is.na(selected$relation_partner.id),]
# удалить колонки с именем 'relation_partner*'
selected <- selected[,!(colnames(selected) %in% grep(x = colnames(selected), pattern = 'relation_partner*', value = T))]
# заменить статус NA (если он был не указан) на 0 для простоты работы
selected[is.na(selected$relation), 'relation'] <- 0

## удаление неактивных пользователей
# удалить неактивных в течении activity дней, преобразовав их дату последней активности в POSIXct формат, вычислив разницу во времени в днях и оставить только тех, у кого срок последней активности меньше пороговой
selected <- selected[difftime(Sys.time(), as.POSIXct(selected$last_seen, origin='1970-01-01'), units='d') < activity,]
# удалить более не нужную колонку last_seen
selected <- selected[,!colnames(selected) == 'last_seen.time']

## Учёт чёрного списка
# удаление пользователей с ID, упомянутыми в чёрном списке
selected <- selected[!(selected$uid %in% blacklist$uid),]

# Промежуточный вывод в текстовый файл полученной после предварительной фильтрации  таблицы
write.table(selected, 'data/primary-HTS.tab', quote = T, sep = '\t', row.names = F, col.names = T)
#------------------------------------------------------------------------------#

### отбор полных дат и неполных дат для экспериментов с RAE, NA даты обнуляются
# подготовить колонку возраста
selected$age <- 0
# разделить на группы с
tempList <- list()
# ... неопределённой датой
tempList[['NA']] <- selected[is.na(selected$bdate),]
tmp <- selected[!is.na(selected$bdate),] # определённой bdate
# ... полной датой
tempList[['Full']] <- tmp[grep('\\d{4}', tmp$bdate),]
# ... неполной датой для RAE
tempList[['Trimm']] <- tmp[grep('\\d{4}', tmp$bdate, invert = T),]

### вывод для RAE
write.table(x = tempList[['Trimm']], file = 'data/data_for_RAE.tab', sep='\t', row.names=F, col.names=T, quote=T)
# ~~~~~~~~ #
# ~~~~~~~~ #
source(file = 'WSS/ReversAgeEstimate.R')
# ~~~~~~~~ #
# ~~~~~~~~ #
### чтение после RAE
tempList[['RAEd']] <- read.table('data/data_RAE_pass.tab', sep = '\t', header = T, stringsAsFactors = F)

### конвертация bdate в возраст age для определённых полных дат
tempList[['Full']]$bdate <- as.character(as.Date(tempList[['Full']][,'bdate'], format='%d.%m.%Y')) # преобразование содержимого поля в даты
tempList[['Full']]$age <- as.numeric(round(difftime(Sys.Date(), as.Date(tempList[['Full']][,'bdate'], format='%Y-%m-%d'), units='d')/365, 1)) # пересчёт в года

tempList[['Full']] <- tempList[['Full']][tempList[['Full']]$age >= minAge,] # удалить моложе чем minAge лет если возраст не NA
tempList[['Full']] <- tempList[['Full']][tempList[['Full']]$age <= maxAge,] # удалить старше чем maxAge лет если возраст не NA
selected <- rbind(tempList[['Full']], tempList[['RAEd']]) # склеить обратно в целый датафрейм полные отфильтрованные и неполные после RAE
selected <- rbind(tempList[['NA']], selected) # склеить обратно суммарно отфильтрованные и с неопределёнными датами
selected[is.na(selected$bdate), 'bdate'] <- 0 # заменить NA даты рождения на нули
rm(tempList)

### контейнер для данных групп, стен и активности
CorrData <- list()


### Получение данных о группах из selected и фильтрация спамерш
# ~~~~~~~~ #
# ~~~~~~~~ #
source(file = 'WSS/CaptureGroupsSubs.R')
# ~~~~~~~~ #
# ~~~~~~~~ #
# удаление 1000ниц (приближение 950) по группам при суммарном T-coeff == 1
selected <- selected[!((selected$ngroups >= 950) & rowSums(selected[,unique(groupsDB$category)]) == 1),]
# удаление удалённых uid из CorrData[['groups']]
CorrData[['groups']] <- CorrData[['groups']][names(CorrData[['groups']]) %in% paste('id', selected$uid, sep = '')]


### Скоринг по T-параметрам и числу групп
# f(ngroups) = lg(ngroups + 1), f(TRNSI) = (T + R + N + S + I) XX (2 0.5 0.5 0.25 0.5)
scoring <- function(x) {
  x <- x[c(unique(groupsDB$category), 'ngroups')]
  x <- as.integer(x)
  names(x) <- c(unique(groupsDB$category), 'ngroups')
  tmp <- 2 * x['T'] + 0.5 * x['R'] + 0.5 * x['N'] + 0.25 * x['S'] + 0.5 * x['I']
  tmp <- round(tmp - log10(x['ngroups'] + 1), 1)
  names(tmp) <- ''
  return(tmp)
}
selected$score <- apply(selected, 1, scoring)


### Захват мета-данных стен и загрузка комментариев
# ~~~~~~~~ #
# ~~~~~~~~ #
source(file = 'WSS/WallDownload.R')
# ~~~~~~~~ #
# ~~~~~~~~ #

### Подсчёт Т-ключевых слов на стенах
# подсчёт T-слов в комментариях для каждого пользователя
tmp <- sapply(CorrData[['wall']], function(x) length(grep(pattern = paste0(Twords, collapse = '|'), x)))
names(tmp) <- gsub('id', '', names(tmp))
# ограничение tmp по набору имён
tmp <- tmp[names(tmp) %in% selected[which(selected$uid %in% names(tmp)), 'uid']]
# запись в основной датафрейм
selected$Twords <- 0
selected[which(selected$uid %in% names(tmp)), 'Twords'] <- tmp
# повышение score за T-слова по закону log2(Twords) - log(wallsize) + 2 как центрование
selected$score <- selected$score + log2(selected$Twords + 1) - log10(selected$wallsize + 1) + 2
### вывод таблицы
# write.table(selected, 'data/HTS.tab', quote = T, sep = '\t', row.names = F, col.names = T)


### Получение дополнительного скоринга для правильно идеологических
selected$RiId <- 0
for (ideo in ideology) {
  # загрузка файла
  download.file(url = paste0('https://api.vk.com/method/users.search?sex=', gender[[sex]], '&religion=', ideo, '&count=1000', '&access_token=', token), destfile = '/tmp/ideo-reward.txt', method='wget', quiet = F)
  # парсинг JSON
  tmp <- fromJSON(file = '/tmp/ideo-reward.txt')$response
  # преобразование в вектор uid
  tmp[[1]] <- NULL
  tmp <- sapply(tmp, function(x) unlist(x))['uid',]
  # увеличение Score, величина награды 5
  selected[selected$uid %in% tmp,]$score <- selected[selected$uid %in% tmp,]$score + 5
  # задание метки правильной идеологии RiId
  selected[selected$uid %in% tmp,]$RiId <- selected[selected$uid %in% tmp,]$RiId + 1
}

### Получение тем и комментариев в Т-группах #
# ~~~~~~~~ #
# ~~~~~~~~ #
source(file = 'WSS/CaptureGroupActivity.R')
# ~~~~~~~~ #
# ~~~~~~~~ #
# увеличение Score: + ntopic и 1 + ln(ncomm + 1)
selected$score <- selected$score + selected$ntopics + round(log(selected$ncomm + 1), 1)


# сохранение результатов
write.table(file='data/HTS.tab', x=selected, sep='\t', row.names=F, col.names=T, quote=T)

### загрузка фоток
# ~~~~~~~~ #
# ~~~~~~~~ #
source(file = 'WSS/PhotoCapture.R')
# ~~~~~~~~ #
# ~~~~~~~~ #

save.image(file = '.RData')

### функция вывода данных
userdata <- function(cand) {
  v <- selected[selected$uid == cand,]
  print(v)
  print(CorrData[['comments']][[paste0('id', cand)]])
  CorrData[['groups']][[paste0('id', cand)]]
#   CorrData[['wall']][[paste0('id', cand)]]
}

### компактный вывод
head(selected[order(selected$score, decreasing = T), c('uid','first_name','last_name','age','T','R','N','S','I','score','Twords','RiId','ntopics','ncomm')], 20)


