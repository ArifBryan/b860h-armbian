while :
do
  state=$(gpioget aobus-banks 2)
  if [ $state -eq 0 ]
  then
    gpioset periphs-banks 73=1
    poweroff
    gpioset periphs-banks 75=0
    while :
    do :
    done
  else
    gpioset periphs-banks 73=0
    gpioset periphs-banks 75=1
  fi
done