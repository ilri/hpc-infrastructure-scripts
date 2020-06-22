# GlusterFS Recovery Scripts
This is a set of scripts I wrote to help me analyze and fix some issues in our distribute–replicate GlusterFS volumes. In our case we had a series of unfortunate events while replacing a dead storage node and simultaneously expanding our cluster capacity. Somewhere in the process of running `replace-brick`, `remove-brick`, and several `rebalance` operations a whole bunch of files ended up on the "wrong" bricks according to the layout. This was further complicated by me moving one brick's `.glusterfs` directory to `.glusterfs.bak` (just in case, I thought) without realizing that the hardlinks still being present on the brick would cause GlusterFS to take the wrong course during `rebalance` operations.

In short: I was impatient and working on a deadline. You should never need these scripts under normal GlusterFS operation. If you are replacing a dead node or adding new capacity you should do these two things separately and only once the first one is finished!

## Signs Something is Wrong
There are a few obvious signs that something is wrong with your volume, as seen from the FUSE mount point.

1. File names with question marks for status information:

```
-??????????  ? ?     ?        ?            ? htoprc
```

2. Duplicate (or triplicate) files:

```
-rw-rw-r--.  1 aorth aorth  679 Jun  6 13:46 htoprc
-rw-rw-r--.  1 aorth aorth  679 Jun  6 13:46 htoprc
```

3. Files with a sticky bit set (usually owned by root, though not always):

```
---------T. 2 root  root   0 Jul 31 14:15 src.zip
```

## How it Works
GlusterFS uses a distributed hash table (DHT) to find and place files evenly on bricks across the storage cluster. Directories on each brick are assigned a "layout" range using the [*Elastic Hashing Algorithm*](https://www.svennd.be/wp-content/uploads/2018/06/gluster_architecture.pdf) (inspired by Amazon Dynamo) and files are placed accordingly based on their file names (not based on metadata).

For an overly simplified example, imagine a layout range from 0x0000 to 0xffff. Directories on each brick would be assigned equal portions of that range like so:

- 0x0000 to 0x7000
- 0x7001 to 0xffff

GlusterFS hashes each file name like so:

- file1.txt: 0x0311
- file2.txt: 0x90f0

The hash of each file name is compared to the DHT layout of each directory to see where it belongs:

- file1.txt: *0x0000* < **0x0311** < *0x7000*
- file2.txt: *0x7001* < **0x90f0** < *0xffff*

These scripts use the same logic, hashing the file name using [gf_dm_hash.py](https://joejulian.name/post/dht-misses-are-expensive/) and comparing it to the `trusted.glusterfs.dht` extended attribute of each directory to see if the file belongs on that brick or not.

## How to Use these Scripts
These scripts are a lazy, sloppy, and brute force re-implementation of the GlusterFS healing and rebalance processes. Both work by reading a text file consisting of one *relative* file name per line. They are meant to be run on each brick in succession:

- `ghetto-heal.sh` checks if each file exists, is sane, and actually belongs on the brick, and if not, copies it to *every other* brick in the volume. I usually run this first to make sure files get copied everywhere before potentially deleting them with `ghetto-rebalance.sh`.
- `ghetto-rebalance.sh` checks if each file exists, is sane, and actually belongs on the brick, and if not, deletes it.

You can generate the input files by getting a list of files in a particular problematic directory on the FUSE client mount, for example:

```
# find /home/[a-j]* -type f | sed 's./home/..' > /tmp/home-aj-files.txt
```

Or from one of the backend bricks:

```
# find /mnt/gluster/homes/[a-j]* -type f > /tmp/homes-brick-aj-files.txt 
```

Or checking for duplicates on the FUSE client mount:

```
# find /home/[a-j]* -type f | sort | uniq -c | grep -E "^\s+[2-9]" | sed 's/^[[:space:]]\+[[:digit:]]\+[[:space:]]//' | sed 's./home/..' > /tmp/home-aj-duplicates.txt
