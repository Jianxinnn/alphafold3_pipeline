#!/usr/bin/env python3
import sys
import json
import os
import argparse
import string

def parse_custom_fasta(file_path):
    entries = []
    current_header = None
    current_seq_lines = []

    try:
        with open(file_path, 'r') as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                if line.startswith('>'):
                    if current_header:
                        entries.append((current_header, "".join(current_seq_lines)))
                    current_header = line[1:]
                    current_seq_lines = []
                else:
                    current_seq_lines.append(line)
            if current_header:
                entries.append((current_header, "".join(current_seq_lines)))
    except Exception as e:
        print(f"Error reading input file: {e}")
        sys.exit(1)
        
    return entries

def parse_segment(segment):
    # Default values
    seg_type = 'protein'
    content = segment
    count = 1
    
    if '|' in segment:
        parts = segment.split('|')
        first_part = parts[0].lower()
        
        # Check against known types
        if first_part in ['dna', 'rna', 'smiles', 'ccd']:
            seg_type = first_part
            content = parts[1]
            if len(parts) > 2:
                try:
                    count = int(parts[2])
                except ValueError:
                    count = 1
        elif first_part in ['protein']:
             seg_type = 'protein'
             content = parts[1]
             if len(parts) > 2: count = int(parts[2])
        else:
            # If no known type prefix is found, assume it's part of the content 
            # (though the format suggests explicit types for non-protein with |)
            # However, for pure protein, usually no | is used. 
            # If | is present but not a known type, treat as protein? 
            # Or assume the user made a typo? 
            # Let's assume default protein if first part isn't a keyword 
            # UNLESS the content looks like it needs parsing.
            # But wait, SMILES strings can contain characters that might be confusing.
            # We stick to the rule: if starts with 'smiles|', 'ccd|', 'dna|', 'rna|' then parse.
            # Otherwise, treat the whole string as content (likely protein sequence).
            pass
            
    return seg_type, content, count

def get_chain_id(index):
    """
    Generate PDB-style chain IDs: A, B, ..., Z, AA, AB, ...
    """
    chars = string.ascii_uppercase
    if index < 26:
        return chars[index]
    else:
        # 0-based index. 26 -> AA. 
        # But commonly after Z, it might be AA, AB...
        # Let's support simple AA..ZZ for now
        quotient, remainder = divmod(index, 26)
        # quotient 1 (index 26) -> A
        # remainder 0 -> A
        # so index 26 -> AA
        return chars[quotient - 1] + chars[remainder] if quotient > 0 else chars[remainder]


def generate_json(entries, output_dir, force_name=None):
    generated_files = []
    
    for idx, (header, seq_str) in enumerate(entries):
        # Determine name
        header_ids = header.split(':')
        
        # Split sequence string by ':'
        seq_segments = seq_str.split(':')
        
        sequences_list = []
        current_id_idx = 0
        
        for seg in seq_segments:
            seg_type, content, count = parse_segment(seg)
            
            # Get IDs for this segment (handling count)
            segment_ids = []
            for _ in range(count):
                # Generate ID A, B, C ...
                chain_id = get_chain_id(current_id_idx)
                segment_ids.append(chain_id)
                current_id_idx += 1
            
            seq_obj = {}
            if seg_type == 'protein':
                seq_obj['protein'] = {"id": segment_ids, "sequence": content}
            elif seg_type == 'dna':
                seq_obj['dna'] = {"id": segment_ids, "sequence": content}
            elif seg_type == 'rna':
                seq_obj['rna'] = {"id": segment_ids, "sequence": content}
            elif seg_type == 'smiles':
                seq_obj['ligand'] = {"id": segment_ids, "smiles": content}
            elif seg_type == 'ccd':
                 seq_obj['ligand'] = {"id": segment_ids, "ccd": content}
            
            sequences_list.append(seq_obj)
            
        # Determine Task Name
        task_name = None
        if force_name and len(entries) == 1:
            task_name = force_name
        else:
            # Use the first ID from header as base, or generic name
            if header_ids:
                task_name = header_ids[0]
            else:
                task_name = f"job_{idx}"

        data = {
            "name": task_name,
            "modelSeeds": [1],
            "sequences": sequences_list,
            "dialect": "alphafold3",
            "version": 2
        }
        
        # Ensure output filename is safe
        safe_name = "".join([c for c in task_name if c.isalpha() or c.isdigit() or c in ('-','_')]).rstrip()
        if not safe_name: safe_name = "job"
        
        out_path = os.path.join(output_dir, f"{safe_name}.json")
        try:
            with open(out_path, 'w') as f:
                json.dump(data, f, indent=4)
            generated_files.append(out_path)
            print(f"Generated JSON: {out_path}")
        except Exception as e:
            print(f"Error writing JSON to {out_path}: {e}")

    return generated_files

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert custom FASTA to AlphaFold3 JSON")
    parser.add_argument("input_fasta", help="Path to input FASTA file")
    parser.add_argument("output_dir", help="Directory to save output JSON files")
    parser.add_argument("--name", help="Task name (force name if single entry)", default=None)
    
    args = parser.parse_args()
    
    if not os.path.exists(args.output_dir):
        try:
            os.makedirs(args.output_dir)
        except OSError as e:
            print(f"Error creating output directory: {e}")
            sys.exit(1)
            
    entries = parse_custom_fasta(args.input_fasta)
    if not entries:
        print("No entries found in FASTA file.")
        sys.exit(1)
        
    generate_json(entries, args.output_dir, args.name)
